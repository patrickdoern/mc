import Foundation
import Network

public final class LinkFileSystem: FileSystem {
    public let identity: String
    public let displayName: String
    public let homePath = "/"
    private let channel: LinkChannel
    private let condition = NSCondition()
    private var inbox: [UInt32: [LinkMessage]] = [0: []]
    private var nextID: UInt32 = 1
    private var isReady = false
    private var isEnded = false

    private static let connectTimeout: TimeInterval = 30
    private static let answerTimeout: TimeInterval = 30

    public convenience init(target: LinkTarget, name: String, identity: LinkIdentity, operation: FileOperation, pairing: (String) -> Void) throws {
        try self.init(target: target, endpoint: .service(name: target.name, type: LinkProtocol.serviceType, domain: "local.", interface: nil), name: name, identity: identity, operation: operation, pairing: pairing)
    }

    init(target: LinkTarget, endpoint: NWEndpoint, name: String, identity: LinkIdentity, operation: FileOperation, pairing: (String) -> Void) throws {
        self.identity = target.displayName
        displayName = target.displayName
        let queue = DispatchQueue(label: "digital.doern.mc.link.client")
        channel = LinkChannel(NWConnection(to: endpoint, using: LinkChannel.parameters(identity: identity, queue: queue)), queue: queue)
        channel.start(
            ready: { [weak self] in self?.update { $0.isReady = true } },
            frame: { [weak self] frame in self?.update { $0.inbox[frame.requestID]?.append(frame.message) } },
            end: { [weak self] in self?.update { $0.isEnded = true } }
        )
        do {
            try pair(name: name, identity: identity, operation: operation, pairing: pairing)
        } catch {
            channel.cancel()
            throw error
        }
    }

    deinit { channel.cancel() }

    public var isDisconnected: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isEnded
    }

    public func disconnect() {
        channel.cancel()
    }

    private func pair(name: String, identity: LinkIdentity, operation: FileOperation, pairing: (String) -> Void) throws {
        guard try wait(until: Date() + Self.connectTimeout, cancelling: operation, for: { isReady ? true : nil }) != nil else { throw unreachable }
        channel.send([LinkFrame(requestID: 0, message: .hello(version: LinkProtocol.version, name: name))])
        guard let hello = try wait(until: Date() + Self.connectTimeout, cancelling: operation, for: { take(0) }) else { throw unreachable }
        guard case .hello(let version, _) = hello else { throw violated() }
        do {
            try LinkProtocol.checkVersion(version)
        } catch {
            throw FileError("\(displayName): \(error.localizedDescription)")
        }
        pairing(LinkIdentity.pairingCode(identity.fingerprint, channel.peerFingerprint))
        let decision = try wait(until: Date() + LinkProtocol.pairingTimeout, cancelling: operation, for: { take(0) })
        switch decision {
        case .done?: forget(0)
        case .error(let text)?: throw FileError("\(displayName): \(text)")
        case nil: throw FileError("\(displayName): " + localized("Keine Bestätigung innerhalb von 60 Sekunden"))
        case .some: throw violated()
        }
    }

    public func list(_ path: String) throws -> [FileEntry] {
        let id = post(.list(path))
        defer { forget(id) }
        var entries: [FileEntry] = []
        while true {
            guard case .entries(let batch, let more) = try answer(id) else { throw violated() }
            entries += batch
            if !more { return entries }
        }
    }

    public func stat(_ path: String) throws -> FileEntry {
        guard case .entry(let entry) = try request(.stat(path)) else { throw violated() }
        return entry
    }

    public func statFollowingLinks(_ path: String) throws -> FileEntry {
        guard case .entry(let entry) = try request(.statFollowingLinks(path)) else { throw violated() }
        return entry
    }

    public func readLink(_ path: String) throws -> String {
        guard case .text(let target) = try request(.readLink(path)) else { throw violated() }
        return target
    }

    public func openReader(_ path: String) throws -> FileReader {
        guard case .handle(let handle) = try request(.openRead(path)) else { throw violated() }
        return LinkReader(owner: self, handle: handle)
    }

    public func makeDirectory(_ path: String) throws { try perform(.makeDirectory(path)) }
    public func removeFile(_ path: String) throws { try perform(.removeFile(path)) }
    public func removeDirectory(_ path: String) throws { try perform(.removeDirectory(path)) }
    public func rename(_ from: String, _ to: String) throws { try perform(.rename(from, to)) }
    public func makeSymlink(_ path: String, target: String) throws { try perform(.makeSymlink(path, target: target)) }
    public func setModified(_ path: String, _ date: Date) throws { try perform(.setModified(path, date)) }
    public func setPermissions(_ path: String, _ mode: UInt16) throws { try perform(.setPermissions(path, mode)) }

    public func openWriter(_ path: String, permissions: UInt16) throws -> FileWriter {
        _ = try request(.openWrite(path, permissions: permissions))
        throw violated()
    }

    private func perform(_ message: LinkMessage) throws {
        guard case .done = try request(message) else { throw violated() }
    }

    fileprivate func request(_ message: LinkMessage) throws -> LinkMessage {
        let id = post(message)
        defer { forget(id) }
        return try answer(id)
    }

    fileprivate func post(_ message: LinkMessage) -> UInt32 {
        let id = update { system in
            let id = system.nextID
            system.nextID = system.nextID % UInt32.max + 1
            system.inbox[id] = []
            return id
        }
        channel.send([LinkFrame(requestID: id, message: message)])
        return id
    }

    fileprivate func answer(_ id: UInt32) throws -> LinkMessage {
        guard let message = try wait(until: Date() + Self.answerTimeout, for: { take(id) }) else {
            channel.cancel()
            throw lost
        }
        if case .error(let text) = message { throw FileError(text) }
        return message
    }

    fileprivate func forget(_ id: UInt32) {
        update { $0.inbox[id] = nil }
    }

    fileprivate func violated() -> FileError {
        channel.cancel()
        return lost
    }

    private var lost: FileError { FileError(localized("Die Verbindung zu %@ ist abgebrochen", displayName as NSString)) }

    private var unreachable: FileError { FileError(localized("Keine Verbindung zu %@", displayName as NSString)) }

    private func take(_ id: UInt32) -> LinkMessage? {
        guard inbox[id]?.isEmpty == false else { return nil }
        return inbox[id]?.removeFirst()
    }

    private func wait<T>(until deadline: Date, cancelling operation: FileOperation? = nil, for value: () -> T?) throws -> T? {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let value = value() { return value }
            if isEnded { throw isReady ? lost : unreachable }
            try operation?.checkCancelled()
            let now = Date()
            if now >= deadline { return nil }
            condition.wait(until: operation == nil ? deadline : min(deadline, now + 0.1))
        }
    }

    @discardableResult
    private func update<T>(_ change: (LinkFileSystem) -> T) -> T {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }
        return change(self)
    }
}

private final class LinkReader: FileReader {
    private static let depth = 4

    private let owner: LinkFileSystem
    private let handle: UInt32
    private var pending: [UInt32] = []
    private var buffer = Data()
    private var atEnd = false
    private var closed = false

    init(owner: LinkFileSystem, handle: UInt32) {
        self.owner = owner
        self.handle = handle
    }

    deinit { close() }

    func read(into target: UnsafeMutableRawBufferPointer) throws -> Int {
        if buffer.isEmpty && !atEnd {
            while pending.count < Self.depth { pending.append(owner.post(.read(handle: handle, length: UInt32(LinkProtocol.maximumBlock)))) }
            let id = pending.removeFirst()
            defer { owner.forget(id) }
            guard case .data(let data) = try owner.answer(id) else { throw owner.violated() }
            buffer = data
            atEnd = data.isEmpty
        }
        let count = min(buffer.count, target.count)
        buffer.copyBytes(to: target, count: count)
        buffer.removeFirst(count)
        return count
    }

    func close() {
        guard !closed else { return }
        closed = true
        pending.forEach(owner.forget)
        _ = try? owner.request(.close(handle: handle))
    }
}
