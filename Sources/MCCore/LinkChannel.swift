import Foundation
import Network
import Security

final class LinkChannel {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = LinkFrameDecoder()
    private var onFrame: ((LinkFrame) -> Void)?
    private var onEnd: (() -> Void)?
    private var ended = false
    private(set) var peerFingerprint = Data()

    init(_ connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    static func parameters(identity: LinkIdentity, queue: DispatchQueue) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity.identity) { sec_protocol_options_set_local_identity(options, local) }
        sec_protocol_options_set_peer_authentication_required(options, true)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in complete(isSelfSigned(trust)) }, queue)
        return NWParameters(tls: tls)
    }

    private static func isSelfSigned(_ trust: sec_trust_t) -> Bool {
        let received = sec_trust_copy_ref(trust).takeRetainedValue()
        guard let leaf = (SecTrustCopyCertificateChain(received) as? [SecCertificate])?.first else { return false }
        var own: SecTrust?
        guard SecTrustCreateWithCertificates(leaf, SecPolicyCreateBasicX509(), &own) == errSecSuccess, let own else { return false }
        SecTrustSetAnchorCertificates(own, [leaf] as CFArray)
        SecTrustSetNetworkFetchAllowed(own, false)
        return SecTrustEvaluateWithError(own, nil)
    }

    func start(ready: @escaping () -> Void, frame: @escaping (LinkFrame) -> Void, end: @escaping () -> Void) {
        onFrame = frame
        onEnd = end
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let certificate = peerCertificate() else { return finish() }
                peerFingerprint = LinkIdentity.fingerprint(of: certificate)
                ready()
                receive()
            case .waiting, .failed, .cancelled:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ frames: [LinkFrame]) {
        connection.send(content: frames.reduce(Data()) { $0 + $1.encoded() }, completion: .idempotent)
    }

    func close(after frames: [LinkFrame]) {
        send(frames)
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in self?.cancel() })
    }

    func cancel() {
        connection.cancel()
    }

    private func peerCertificate() -> SecCertificate? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else { return nil }
        var leaf: SecCertificate?
        sec_protocol_metadata_access_peer_certificate_chain(metadata.securityProtocolMetadata) { certificate in
            if leaf == nil { leaf = sec_certificate_copy_ref(certificate).takeRetainedValue() }
        }
        return leaf
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: LinkProtocol.maximumPayload) { [weak self] data, _, isComplete, error in
            guard let self, !ended else { return }
            if let data { decoder.append(data) }
            do {
                while !ended, let frame = try decoder.next() { onFrame?(frame) }
            } catch {
                return finish()
            }
            if isComplete || error != nil { finish() } else { receive() }
        }
    }

    private func finish() {
        guard !ended else { return }
        ended = true
        connection.cancel()
        let end = onEnd
        onFrame = nil
        onEnd = nil
        end?()
    }
}
