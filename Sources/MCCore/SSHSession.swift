import CLibSSH2
import Foundation

final class SSHSession {
    let handle: OpaquePointer
    private var socketDescriptor: Int32
    private let interaction: SSHInteraction

    private static let initialized: Bool = {
        libssh2_init(0)
        return true
    }()

    init(settings: SSHSettings, interaction: SSHInteraction) throws {
        _ = Self.initialized
        self.interaction = interaction
        socketDescriptor = try Self.connectSocket(host: settings.hostName, port: settings.port)
        guard let handle = libssh2_session_init_ex(nil, nil, nil, nil) else {
            Darwin.close(socketDescriptor)
            throw FileError("SSH-Sitzung konnte nicht angelegt werden")
        }
        self.handle = handle
        libssh2_session_set_blocking(handle, 1)
        libssh2_session_set_timeout(handle, 30_000)
        do {
            guard libssh2_session_handshake(handle, socketDescriptor) == 0 else { throw lastError("Handshake") }
            try verifyHostKey(settings)
            try authenticate(settings)
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        libssh2_session_disconnect_ex(handle, SSH_DISCONNECT_BY_APPLICATION, "bye", "")
        libssh2_session_free(handle)
        Darwin.close(socketDescriptor)
    }

    func lastError(_ context: String) -> FileError {
        var message: UnsafeMutablePointer<CChar>?
        var length: Int32 = 0
        libssh2_session_last_error(handle, &message, &length, 0)
        return FileError("\(context): \(message.map { String(cString: $0) } ?? "unbekannter Fehler")")
    }

    private static func connectSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else { throw FileError("Host nicht gefunden: \(host)") }
        defer { freeaddrinfo(result) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let info = current {
            if let descriptor = connect(info.pointee, timeout: 10_000) { return descriptor }
            current = info.pointee.ai_next
        }
        throw FileError("Verbindung zu \(host):\(port) fehlgeschlagen")
    }

    private static func connect(_ info: addrinfo, timeout: Int32) -> Int32? {
        let descriptor = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
        guard descriptor >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        if Darwin.connect(descriptor, info.ai_addr, info.ai_addrlen) != 0 {
            var poller = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            var failure: Int32 = 0
            var size = socklen_t(MemoryLayout<Int32>.size)
            guard errno == EINPROGRESS, poll(&poller, 1, timeout) == 1,
                  getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &failure, &size) == 0, failure == 0 else {
                Darwin.close(descriptor)
                return nil
            }
        }
        _ = fcntl(descriptor, F_SETFL, flags)
        return descriptor
    }

    private func verifyHostKey(_ settings: SSHSettings) throws {
        var length = 0
        var keyType: Int32 = 0
        guard let key = libssh2_session_hostkey(handle, &length, &keyType), let hosts = libssh2_knownhost_init(handle) else { throw lastError("Hostkey") }
        defer { libssh2_knownhost_free(hosts) }
        _ = libssh2_knownhost_readfile(hosts, settings.knownHostsFile, LIBSSH2_KNOWNHOST_FILE_OPENSSH)
        let knownHostsType = Self.knownHostsKeyType(keyType)
        let mask = LIBSSH2_KNOWNHOST_TYPE_PLAIN | LIBSSH2_KNOWNHOST_KEYENC_RAW | knownHostsType
        let port: Int32 = settings.port == 22 ? -1 : Int32(settings.port)
        var match: UnsafeMutablePointer<libssh2_knownhost>?
        switch libssh2_knownhost_checkp(hosts, settings.hostName, port, key, length, mask, &match) {
        case LIBSSH2_KNOWNHOST_CHECK_MATCH:
            return
        case LIBSSH2_KNOWNHOST_CHECK_MISMATCH:
            throw FileError("Der Hostkey von \(settings.hostName) hat sich geändert. Verbindung abgebrochen.")
        default:
            let name = settings.port == 22 ? settings.hostName : "[\(settings.hostName)]:\(settings.port)"
            guard interaction.trustUnknownHost(name, keyType: Self.keyTypeName(keyType), fingerprint: fingerprint()) else { throw OperationAborted() }
            try remember(hosts, name: name, key: key, length: length, mask: mask, file: settings.knownHostsFile)
        }
    }

    private func remember(_ hosts: OpaquePointer, name: String, key: UnsafePointer<CChar>, length: Int, mask: Int32, file: String) throws {
        var stored: UnsafeMutablePointer<libssh2_knownhost>?
        guard libssh2_knownhost_addc(hosts, name, nil, key, length, nil, 0, mask, &stored) == 0, let stored else { throw lastError("known_hosts") }
        var buffer = [CChar](repeating: 0, count: 2048)
        var written = 0
        guard libssh2_knownhost_writeline(hosts, stored, &buffer, buffer.count, &written, LIBSSH2_KNOWNHOST_FILE_OPENSSH) == 0 else { throw lastError("known_hosts") }
        let line = String(cString: buffer)
        try FileManager.default.createDirectory(atPath: PosixPath.parent(file), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: file) { FileManager.default.createFile(atPath: file, contents: nil, attributes: [.posixPermissions: 0o600]) }
        let output = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        defer { try? output.close() }
        try output.seekToEnd()
        try output.write(contentsOf: Data(line.utf8))
    }

    private func fingerprint() -> String {
        guard let hash = libssh2_hostkey_hash(handle, LIBSSH2_HOSTKEY_HASH_SHA256) else { return "unbekannt" }
        let data = Data(bytes: hash, count: 32)
        return "SHA256:" + data.base64EncodedString().replacingOccurrences(of: "=", with: "")
    }

    private static func knownHostsKeyType(_ type: Int32) -> Int32 {
        switch type {
        case LIBSSH2_HOSTKEY_TYPE_RSA: return LIBSSH2_KNOWNHOST_KEY_SSHRSA
        case LIBSSH2_HOSTKEY_TYPE_DSS: return LIBSSH2_KNOWNHOST_KEY_SSHDSS
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_256: return LIBSSH2_KNOWNHOST_KEY_ECDSA_256
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_384: return LIBSSH2_KNOWNHOST_KEY_ECDSA_384
        case LIBSSH2_HOSTKEY_TYPE_ECDSA_521: return LIBSSH2_KNOWNHOST_KEY_ECDSA_521
        default: return LIBSSH2_KNOWNHOST_KEY_ED25519
        }
    }

    private static func keyTypeName(_ type: Int32) -> String {
        switch type {
        case LIBSSH2_HOSTKEY_TYPE_RSA: return "RSA"
        case LIBSSH2_HOSTKEY_TYPE_DSS: return "DSA"
        case LIBSSH2_HOSTKEY_TYPE_ED25519: return "ED25519"
        default: return "ECDSA"
        }
    }

    private var isAuthenticated: Bool { libssh2_userauth_authenticated(handle) != 0 }

    private func authenticate(_ settings: SSHSettings) throws {
        let user = settings.user
        guard let list = libssh2_userauth_list(handle, user, UInt32(user.utf8.count)) else {
            if isAuthenticated { return }
            throw lastError("Anmeldung")
        }
        let methods = String(cString: list).split(separator: ",").map(String.init)
        if methods.contains("publickey") {
            authenticateWithAgent(settings)
            if isAuthenticated { return }
            for file in settings.identityFiles where FileManager.default.fileExists(atPath: file) {
                authenticateWithKeyFile(file, user: user)
                if isAuthenticated { return }
            }
        }
        if methods.contains("password") {
            for _ in 0..<3 {
                guard let password = interaction.requestSecret("Passwort für \(user)@\(settings.hostName):") else { throw OperationAborted() }
                if libssh2_userauth_password_ex(handle, user, UInt32(user.utf8.count), password, UInt32(password.utf8.count), nil) == 0 { return }
            }
        } else if methods.contains("keyboard-interactive") {
            try authenticateInteractively(settings)
            if isAuthenticated { return }
        }
        throw FileError("Anmeldung an \(settings.hostName) als \(user) fehlgeschlagen")
    }

    private func authenticateWithAgent(_ settings: SSHSettings) {
        guard let agent = libssh2_agent_init(handle) else { return }
        defer {
            libssh2_agent_disconnect(agent)
            libssh2_agent_free(agent)
        }
        if let path = settings.identityAgent { libssh2_agent_set_identity_path(agent, path) }
        guard libssh2_agent_connect(agent) == 0, libssh2_agent_list_identities(agent) == 0 else { return }
        var previous: UnsafeMutablePointer<libssh2_agent_publickey>?
        var identity: UnsafeMutablePointer<libssh2_agent_publickey>?
        while libssh2_agent_get_identity(agent, &identity, previous) == 0, let current = identity {
            if libssh2_agent_userauth(agent, settings.user, current) == 0 { return }
            previous = current
        }
    }

    private func authenticateWithKeyFile(_ file: String, user: String) {
        guard libssh2_userauth_publickey_fromfile_ex(handle, user, UInt32(user.utf8.count), nil, file, nil) == LIBSSH2_ERROR_FILE,
              let passphrase = interaction.requestSecret("Passphrase für \(PosixPath.name(file)):") else { return }
        _ = libssh2_userauth_publickey_fromfile_ex(handle, user, UInt32(user.utf8.count), nil, file, passphrase)
    }

    private func authenticateInteractively(_ settings: SSHSettings) throws {
        let context = KeyboardInteractiveContext(interaction: interaction, label: "\(settings.user)@\(settings.hostName)")
        let pointer = Unmanaged.passRetained(context)
        defer { pointer.release() }
        libssh2_session_abstract(handle).pointee = pointer.toOpaque()
        _ = libssh2_userauth_keyboard_interactive_ex(handle, settings.user, UInt32(settings.user.utf8.count)) { _, _, _, _, count, prompts, responses, abstract in
            guard let abstract, let prompts, let responses, let context = abstract.pointee else { return }
            let interactive = Unmanaged<KeyboardInteractiveContext>.fromOpaque(context).takeUnretainedValue()
            for index in 0..<Int(count) {
                let prompt = prompts[index]
                let text = prompt.text.map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(prompt.length)), as: UTF8.self) } ?? ""
                let answer = interactive.interaction.requestSecret("\(interactive.label): \(text)") ?? ""
                responses[index] = LIBSSH2_USERAUTH_KBDINT_RESPONSE(text: strdup(answer), length: UInt32(answer.utf8.count))
            }
        }
    }
}

private final class KeyboardInteractiveContext {
    let interaction: SSHInteraction
    let label: String

    init(interaction: SSHInteraction, label: String) {
        self.interaction = interaction
        self.label = label
    }
}
