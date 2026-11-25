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

    init(allow: Bool?) throws {
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
        server = LinkServer(name: "Server", folders: [share.path], identity: serverIdentity, loopback: true) { [weak self] event in
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

    static func operation() -> FileOperation {
        FileOperation(handlers: OperationHandlers(progress: { _ in }, resolveConflict: { _ in .cancel }, resolveFailure: { _, _ in .abort }))
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
        #expect(failure { try system.makeDirectory(folder + "/neu") }?.localizedDescription == readOnly)
        #expect(failure { try system.removeFile(folder + "/small.txt") }?.localizedDescription == readOnly)
        #expect(failure { try system.rename(folder + "/small.txt", folder + "/x.txt") }?.localizedDescription == readOnly)
        #expect(failure { try system.setModified(folder + "/small.txt", Date()) }?.localizedDescription == readOnly)
        #expect(failure { _ = try system.openWriter(folder + "/neu.txt", permissions: 0o644) }?.localizedDescription == readOnly)
        let outside = localized("Außerhalb der Freigabe")
        #expect(failure { _ = try system.list(folder + "/outside") }?.localizedDescription == outside)
        #expect(failure { _ = try system.readAll(folder + "/outside/secret.txt") }?.localizedDescription == outside)
        #expect(failure { _ = try system.list("/..") }?.localizedDescription == outside)
        #expect(try system.list(folder).count == 4)
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
        harness.stopServer()
        let error = failure { _ = try system.list("/") }
        #expect(error?.localizedDescription == localized("Die Verbindung zu %@ ist abgebrochen", "mc://Server" as NSString))
    }
}
