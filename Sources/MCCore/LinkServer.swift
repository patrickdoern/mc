import Foundation
import Network

public final class LinkServer {
    public enum Event {
        case waiting
        case request(id: UUID, name: String, code: String)
        case requestExpired
        case connected(String)
        case reading(name: String, path: String)
        case writing(name: String, path: String)
        case deleting(name: String, path: String)
        case changing(name: String, path: String)
        case incompatible(String)
        case failed(Error)
    }

    private final class Peer {
        let id = UUID()
        let channel: LinkChannel
        var name = ""
        var share: LinkShare?
        var timeout: DispatchWorkItem?

        init(channel: LinkChannel) {
            self.channel = channel
        }
    }

    private let name: String
    private let folders: [String]
    private let writable: Bool
    private let identity: LinkIdentity
    private let loopback: Bool
    private let onEvent: (Event) -> Void
    private let queue = DispatchQueue(label: "digital.doern.mc.link.server")
    private var listener: NWListener?
    private var peers: [Peer] = []
    private var partner: Peer?
    private var stopped = false

    public init(name: String, folders: [String], writable: Bool, identity: LinkIdentity, loopback: Bool = false, onEvent: @escaping (Event) -> Void) {
        self.name = name
        self.folders = folders
        self.writable = writable
        self.identity = identity
        self.loopback = loopback
        self.onEvent = onEvent
    }

    public var port: UInt16? {
        queue.sync { listener?.port?.rawValue }
    }

    public func start() throws {
        let parameters = LinkChannel.parameters(identity: identity, queue: queue)
        if loopback { parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any) }
        let listener = try NWListener(using: parameters)
        if !loopback {
            listener.service = NWListener.Service(name: name, type: LinkProtocol.serviceType, domain: nil, txtRecord: NWTXTRecord(["v": String(LinkProtocol.version)]))
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.report(.waiting)
            case .waiting(let error), .failed(let error):
                self?.report(.failed(error))
                self?.listener?.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        queue.sync { self.listener = listener }
        listener.start(queue: queue)
    }

    public func decide(_ id: UUID, allow: Bool) {
        queue.async { [self] in
            guard let peer = partner, peer.id == id, peer.share == nil else { return }
            peer.timeout?.cancel()
            if allow {
                peer.share = LinkShare(folders: folders, writable: writable)
                peer.channel.send([LinkFrame(requestID: 0, message: .done)])
                report(.connected(peer.name))
            } else {
                partner = nil
                peer.channel.close(after: [LinkFrame(requestID: 0, message: .error(localized("Die Verbindung wurde abgelehnt")))])
                report(.waiting)
            }
        }
    }

    public func stop() {
        queue.sync {
            stopped = true
            listener?.cancel()
            peers.forEach { peer in
                peer.share?.end()
                peer.channel.cancel()
            }
            partner = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped else { return connection.cancel() }
        let peer = Peer(channel: LinkChannel(connection, queue: queue))
        peers.append(peer)
        peer.channel.start(
            ready: { [weak self, weak peer] in
                guard let self, let peer else { return }
                let timeout = DispatchWorkItem { [weak self, weak peer] in
                    guard let peer else { return }
                    self?.expire(peer)
                }
                peer.timeout = timeout
                queue.asyncAfter(deadline: .now() + LinkProtocol.pairingTimeout, execute: timeout)
            },
            frame: { [weak self, weak peer] frame in
                guard let peer else { return }
                self?.receive(frame, from: peer)
            },
            end: { [weak self, weak peer] in
                guard let peer else { return }
                self?.end(peer)
            }
        )
    }

    private func receive(_ frame: LinkFrame, from peer: Peer) {
        if let share = peer.share {
            let answer = share.answer(frame)
            if let event = Self.event(for: frame.message, from: peer.name), !answer.contains(where: { $0.message.isError }) { report(event) }
            return peer.channel.send(answer)
        }
        guard peer.name.isEmpty, case .hello(let version, let name, _) = frame.message else { return peer.channel.cancel() }
        peer.name = name
        do {
            try LinkProtocol.checkVersion(version)
        } catch {
            report(.incompatible(name))
            let hello = LinkFrame(requestID: 0, message: .hello(version: LinkProtocol.version, name: self.name, writable: false))
            return peer.channel.close(after: [hello, LinkFrame(requestID: 0, message: .error(error.localizedDescription))])
        }
        let hello = LinkFrame(requestID: 0, message: .hello(version: LinkProtocol.version, name: self.name, writable: writable))
        if let partner {
            let reason = partner.share == nil ? localized("Eine andere Verbindungsanfrage ist noch offen") : localized("Bereits mit %@ verbunden", partner.name as NSString)
            return peer.channel.close(after: [hello, LinkFrame(requestID: 0, message: .error(reason))])
        }
        partner = peer
        peer.channel.send([hello])
        report(.request(id: peer.id, name: name, code: LinkIdentity.pairingCode(identity.fingerprint, peer.channel.peerFingerprint)))
    }

    private static func event(for message: LinkMessage, from name: String) -> Event? {
        switch message {
        case .openRead(let path): return .reading(name: name, path: path)
        case .openWrite(let path, _): return .writing(name: name, path: path)
        case .removeFile(let path), .removeDirectory(let path), .trash(let path): return .deleting(name: name, path: path)
        case .rename(let path, _), .makeDirectory(let path), .makeSymlink(let path, _), .setModified(let path, _), .setPermissions(let path, _): return .changing(name: name, path: path)
        default: return nil
        }
    }

    private func expire(_ peer: Peer) {
        guard peer === partner else { return peer.channel.cancel() }
        partner = nil
        peer.channel.close(after: [LinkFrame(requestID: 0, message: .error(localized("Keine Bestätigung innerhalb von 60 Sekunden")))])
        report(.requestExpired)
        report(.waiting)
    }

    private func end(_ peer: Peer) {
        peer.timeout?.cancel()
        peer.share?.end()
        peers.removeAll { $0 === peer }
        guard peer === partner else { return }
        partner = nil
        if peer.share == nil { report(.requestExpired) }
        report(.waiting)
    }

    private func report(_ event: Event) {
        guard !stopped else { return }
        onEvent(event)
    }
}
