import Foundation
import Network
import Testing
@testable import MCCore

private final class EventLog {
    private let condition = NSCondition()
    private var events: [LinkServer.Event] = []

    func record(_ event: LinkServer.Event) {
        condition.lock()
        events.append(event)
        condition.broadcast()
        condition.unlock()
    }

    func count(_ match: (LinkServer.Event) -> Bool) -> Int {
        condition.lock()
        defer { condition.unlock() }
        return events.filter(match).count
    }

    func requestIDs() -> [UUID] {
        condition.lock()
        defer { condition.unlock() }
        return events.compactMap { event in
            guard case .request(let id, _, _) = event else { return nil }
            return id
        }
    }

    func wait(count: Int = 1, _ match: (LinkServer.Event) -> Bool) -> Bool {
        let deadline = Date() + 10
        condition.lock()
        defer { condition.unlock() }
        while events.filter(match).count < count {
            guard condition.wait(until: deadline) else { return events.filter(match).count >= count }
        }
        return true
    }
}

private final class Harness {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mc-link-" + UUID().uuidString)
    let shareName = "Freigabe"
    let big = Data((0..<(600 * 1024 + 123)).map { UInt8(truncatingIfNeeded: $0 * 31 + $0 / 7) })
    let events = EventLog()
    private let serverLabel = "digital.doern.mc.link.test." + UUID().uuidString
    private let clientLabel = "digital.doern.mc.link.test." + UUID().uuidString
    let serverIdentity: LinkIdentity
    let clientIdentity: LinkIdentity
    private var server: LinkServer!

    init(allow: Bool?, writable: Bool = false) throws {
        let share = root.appendingPathComponent(shareName)
        let outside = root.appendingPathComponent("Außen")
        try FileManager.default.createDirectory(at: share.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("Hallo".utf8).write(to: share.appendingPathComponent("small.txt"))
        try big.write(to: share.appendingPathComponent("big.bin"))
        try Data("geheim".utf8).write(to: outside.appendingPathComponent("secret.txt"))
        try FileManager.default.createSymbolicLink(at: share.appendingPathComponent("outside"), withDestinationURL: outside)
        serverIdentity = try LinkIdentity.load(label: serverLabel)
        clientIdentity = try LinkIdentity.load(label: clientLabel)
        server = LinkServer(name: "Server", folders: [share.path], writable: writable, identity: serverIdentity, loopback: true) { [weak self] event in
            self?.events.record(event)
            if case .request(let id, _, _) = event, let allow { self?.server.decide(id, allow: allow) }
        }
        try server.start()
        guard events.wait(Self.isWaiting) else { throw FileError("Server lauscht nicht") }
    }

    func connect(as name: String = "Client", operation: FileOperation = Harness.operation(), pairing: (String) -> Void = { _ in }) throws -> LinkFileSystem {
        guard let port = server.port.flatMap(NWEndpoint.Port.init(rawValue:)) else { throw FileError("Kein Port") }
        return try LinkFileSystem(target: LinkTarget(name: "Server"), endpoint: .hostPort(host: "127.0.0.1", port: port), name: name, identity: clientIdentity, operation: operation, pairing: pairing)
    }

    func decide(_ id: UUID, allow: Bool) {
        server.decide(id, allow: allow)
    }

    func synchronize() {
        _ = server.port
    }

    func stopServer() {
        server.stop()
    }

    func finish() {
        server.stop()
        LinkIdentity.remove(label: serverLabel)
        LinkIdentity.remove(label: clientLabel)
        try? FileManager.default.removeItem(at: root)
    }

    static func operation(_ options: TransferOptions = TransferOptions()) -> FileOperation {
        FileOperation(handlers: OperationHandlers(progress: { _ in }, resolveConflict: { _ in .cancel }, resolveFailure: { _, _ in .abort }), options: options)
    }

    static func isWaiting(_ event: LinkServer.Event) -> Bool {
        if case .waiting = event { return true }
        return false
    }

    static func isRequest(_ event: LinkServer.Event) -> Bool {
        if case .request = event { return true }
        return false
    }

    static func isExpired(_ event: LinkServer.Event) -> Bool {
        if case .requestExpired = event { return true }
        return false
    }
}

private func isOpen(_ path: String) -> Bool {
    guard let real = realpath(path, nil) else { return false }
    defer { free(real) }
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    return (0..<getdtablesize()).contains { fcntl($0, F_GETPATH, &buffer) == 0 && strcmp(buffer, real) == 0 }
}

private func failure(_ body: () throws -> Void) -> Error? {
    do {
        try body()
        return nil
    } catch {
        return error
    }
}

@Suite(.serialized) struct LinkLoopbackTests {
    @Test func readsShareAfterPairing() throws {
        let harness = try Harness(allow: true)
        defer { harness.finish() }
        var shownCode = ""
        let system = try harness.connect { shownCode = $0 }
        let folder = "/" + harness.shareName
        #expect(harness.events.wait { if case .connected("Client") = $0 { return true }; return false })
        #expect(harness.events.count { if case .request(_, "Client", shownCode) = $0 { return true }; return false } == 1)
        #expect(shownCode == LinkIdentity.pairingCode(harness.clientIdentity.fingerprint, harness.serverIdentity.fingerprint))
        #expect(system.displayName == "mc://Server")
        #expect(try system.list("/").map(\.name) == [harness.shareName])
        #expect(try system.list(folder).map(\.name).sorted() == ["big.bin", "outside", "small.txt", "sub"])
        let small = try system.stat(folder + "/small.txt")
        #expect(small.size == 5 && !small.isDirectory)
        #expect(try system.stat(folder + "/sub").isDirectory)
        #expect(try system.stat(folder + "/outside").isSymlink)
        #expect(try system.readAll(folder + "/small.txt") == Data("Hallo".utf8))
        #expect(try system.readAll(folder + "/big.bin") == harness.big)
        #expect(harness.events.wait { if case .reading(name: "Client", path: folder + "/big.bin") = $0 { return true }; return false })
        system.disconnect()
        #expect(harness.events.wait(count: 2, Harness.isWaiting))
    }

    @Test func rejectsWritingAndAccessOutside() throws {
        let harness = try Harness(allow: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let folder = "/" + harness.shareName
        let readOnly = localized("Die Freigabe ist nur lesbar")
        #expect(!system.isWritable)
        #expect(failure { try system.makeDirectory(folder + "/neu") }?.localizedDescription == readOnly)
        #expect(failure { try system.removeFile(folder + "/small.txt") }?.localizedDescription == readOnly)
        #expect(failure { try system.rename(folder + "/small.txt", folder + "/x.txt") }?.localizedDescription == readOnly)
        #expect(failure { try system.setModified(folder + "/small.txt", Date()) }?.localizedDescription == readOnly)
        #expect(failure { _ = try system.openWriter(folder + "/neu.txt", permissions: 0o644) }?.localizedDescription == readOnly)
        #expect(failure { try system.trash(folder + "/small.txt") }?.localizedDescription == readOnly)
        #expect(!FileManager.default.fileExists(atPath: harness.root.appendingPathComponent(harness.shareName + "/neu.txt").path))
        let outside = localized("Außerhalb der Freigabe")
        #expect(failure { _ = try system.list(folder + "/outside") }?.localizedDescription == outside)
        #expect(failure { _ = try system.readAll(folder + "/outside/secret.txt") }?.localizedDescription == outside)
        #expect(failure { _ = try system.list("/..") }?.localizedDescription == outside)
        #expect(try system.list(folder).count == 4)
    }

    @Test func changesWritableShare() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let folder = "/" + harness.shareName
        try system.makeDirectory(folder + "/neu")
        try system.rename(folder + "/small.txt", folder + "/neu/small.txt")
        try system.removeFile(folder + "/neu/small.txt")
        #expect(try system.list(folder + "/neu").isEmpty)
        #expect(failure { try system.makeDirectory(folder + "/outside/neu") }?.localizedDescription == localized("Außerhalb der Freigabe"))
        #expect(failure { try system.removeDirectory(folder) }?.localizedDescription == localized("Freigegebene Ordner lassen sich nicht ändern"))
        #expect(harness.events.wait { if case .changing(name: "Client", path: folder + "/neu") = $0 { return true }; return false })
        #expect(harness.events.wait { if case .deleting(name: "Client", path: folder + "/neu/small.txt") = $0 { return true }; return false })
        #expect(harness.events.count { if case .changing(_, folder + "/outside/neu") = $0 { return true }; return false } == 0)
        #expect(harness.events.count { if case .deleting(_, folder) = $0 { return true }; return false } == 0)
    }

    @Test func uploadsLargeFile() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        #expect(system.isWritable)
        var generator = SystemRandomNumberGenerator()
        let content = Data((0..<(3 * 1024 * 1024 + 4321)).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let path = "/" + harness.shareName + "/upload.bin"
        try system.writeAll(content, to: path, permissions: 0o644)
        #expect(FileManager.default.contents(atPath: harness.root.appendingPathComponent(harness.shareName + "/upload.bin").path) == content)
        #expect(try system.readAll(path) == content)
        #expect(harness.events.wait { if case .writing(name: "Client", path: path) = $0 { return true }; return false })
    }

    @Test func savesExistingFileSafely() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let folder = "/" + harness.shareName
        try system.writeAllSafely(Data("Neuer Inhalt".utf8), to: folder + "/small.txt", permissions: 0o644)
        let share = harness.root.appendingPathComponent(harness.shareName)
        #expect(FileManager.default.contents(atPath: share.appendingPathComponent("small.txt").path) == Data("Neuer Inhalt".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: share.path).sorted() == ["big.bin", "outside", "small.txt", "sub"])
    }

    @Test func abortClosesFileOnServer() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let local = harness.root.appendingPathComponent(harness.shareName + "/abgebrochen.bin").path
        let writer = try system.openWriter("/" + harness.shareName + "/abgebrochen.bin", permissions: 0o644)
        let block = Data(repeating: 7, count: LinkProtocol.maximumBlock * 3)
        try block.withUnsafeBytes { try writer.write($0) }
        #expect(isOpen(local))
        writer.abort()
        #expect(!isOpen(local))
        #expect(try system.list("/" + harness.shareName).count == 5)
    }

    @Test func trashesOnServer() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let name = "mc-link-trash-" + UUID().uuidString
        let local = harness.root.appendingPathComponent(harness.shareName + "/" + name)
        try Data("weg".utf8).write(to: local)
        let trash = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: harness.root, create: false)
        let trashed = trash.appendingPathComponent(name)
        try Harness.operation().delete(["/" + harness.shareName + "/" + name], on: system, trash: true)
        #expect(!FileManager.default.fileExists(atPath: local.path))
        #expect(FileManager.default.contents(atPath: trashed.path) == Data("weg".utf8))
        try FileManager.default.removeItem(at: trashed)
        #expect(harness.events.wait { if case .deleting(name: "Client", path: "/" + harness.shareName + "/" + name) = $0 { return true }; return false })
    }

    @Test func copiesTreeWithAttributes() throws {
        let harness = try Harness(allow: true, writable: true)
        defer { harness.finish() }
        let system = try harness.connect()
        let source = harness.root.appendingPathComponent("Quelle")
        let stamp = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("innen"), withIntermediateDirectories: true)
        try Data("eins".utf8).write(to: source.appendingPathComponent("eins.txt"))
        try Data("zwei".utf8).write(to: source.appendingPathComponent("innen/zwei.txt"))
        try LocalFileSystem.shared.setPermissions(source.appendingPathComponent("innen/zwei.txt").path, 0o640)
        for item in ["eins.txt", "innen/zwei.txt", "innen", ""] { try LocalFileSystem.shared.setModified(source.appendingPathComponent(item).path, stamp) }
        let target = "/" + harness.shareName + "/Kopie"
        try Harness.operation(TransferOptions(preserveAttributes: true)).copy([Transfer(source: source.path, destination: target)], from: LocalFileSystem.shared, to: system)
        let copy = harness.root.appendingPathComponent(harness.shareName + "/Kopie")
        #expect(FileManager.default.contents(atPath: copy.appendingPathComponent("eins.txt").path) == Data("eins".utf8))
        #expect(FileManager.default.contents(atPath: copy.appendingPathComponent("innen/zwei.txt").path) == Data("zwei".utf8))
        for item in ["eins.txt", "innen/zwei.txt", "innen", ""] { #expect(try LocalFileSystem.shared.stat(copy.appendingPathComponent(item).path).modified == stamp) }
        #expect(try LocalFileSystem.shared.stat(copy.appendingPathComponent("innen/zwei.txt").path).permissions & 0o777 == 0o640)
    }

    @Test func reportsRefusalByServer() throws {
        let harness = try Harness(allow: false)
        defer { harness.finish() }
        let error = failure { _ = try harness.connect() }
        #expect(error?.localizedDescription == "mc://Server: " + localized("Die Verbindung wurde abgelehnt"))
        #expect(harness.events.wait(count: 2, Harness.isWaiting))
    }

    @Test func rejectsSecondPeer() throws {
        let harness = try Harness(allow: true)
        defer { harness.finish() }
        let first = try harness.connect()
        let error = failure { _ = try harness.connect(as: "Zweiter") }
        #expect(error?.localizedDescription == "mc://Server: " + localized("Bereits mit %@ verbunden", "Client" as NSString))
        #expect(try first.list("/").count == 1)
        #expect(harness.events.count(Harness.isRequest) == 1)
    }

    @Test func rejectsSecondRequestAndCancelsPairing() throws {
        let harness = try Harness(allow: nil)
        defer { harness.finish() }
        let operation = Harness.operation()
        let done = DispatchSemaphore(value: 0)
        var pending: Error?
        DispatchQueue.global().async {
            pending = failure { _ = try harness.connect(operation: operation) }
            done.signal()
        }
        #expect(harness.events.wait(Harness.isRequest))
        let error = failure { _ = try harness.connect(as: "Zweiter") }
        #expect(error?.localizedDescription == "mc://Server: " + localized("Eine andere Verbindungsanfrage ist noch offen"))
        operation.cancel()
        #expect(done.wait(timeout: .now() + 10) == .success)
        #expect(pending is OperationAborted)
        #expect(harness.events.wait(Harness.isExpired))
    }

    @Test func lateDecisionDoesNotAdmitNextRequest() throws {
        let harness = try Harness(allow: nil)
        defer { harness.finish() }
        let first = Harness.operation()
        let firstDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = failure { _ = try harness.connect(operation: first) }
            firstDone.signal()
        }
        #expect(harness.events.wait(Harness.isRequest))
        first.cancel()
        #expect(firstDone.wait(timeout: .now() + 10) == .success)
        #expect(harness.events.wait(Harness.isExpired))
        let second = Harness.operation()
        let secondDone = DispatchSemaphore(value: 0)
        var secondResult: Error?
        DispatchQueue.global().async {
            secondResult = failure { _ = try harness.connect(as: "Zweiter", operation: second) }
            secondDone.signal()
        }
        #expect(harness.events.wait(count: 2, Harness.isRequest))
        let ids = harness.events.requestIDs()
        #expect(ids.count == 2 && ids[0] != ids[1])
        harness.decide(ids[0], allow: true)
        harness.synchronize()
        #expect(secondDone.wait(timeout: .now() + 0.5) == .timedOut)
        #expect(harness.events.count { if case .connected = $0 { return true }; return false } == 0)
        harness.decide(ids[1], allow: true)
        #expect(secondDone.wait(timeout: .now() + 10) == .success)
        #expect(secondResult == nil)
        #expect(harness.events.wait { if case .connected("Zweiter") = $0 { return true }; return false })
    }

    @Test func reportsLostConnection() throws {
        let harness = try Harness(allow: true)
        defer { harness.finish() }
        let system = try harness.connect()
        #expect(!system.isDisconnected)
        harness.stopServer()
        let error = failure { _ = try system.list("/") }
        #expect(error?.localizedDescription == localized("Die Verbindung zu %@ ist abgebrochen", "mc://Server" as NSString))
        #expect(system.isDisconnected)
    }
}
