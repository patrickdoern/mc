import Foundation
import Testing
@testable import MCCore

private func decodeAll(_ data: Data) throws -> [LinkFrame] {
    var decoder = LinkFrameDecoder()
    decoder.append(data)
    var frames: [LinkFrame] = []
    while let frame = try decoder.next() { frames.append(frame) }
    return frames
}

private func header(length: UInt32, type: UInt8, requestID: UInt32 = 1) -> Data {
    var writer = LinkPayloadWriter()
    writer.uint32(length)
    writer.byte(type)
    writer.uint32(requestID)
    return writer.data
}

@Suite struct LinkProtocolTests {
    let entry = FileEntry(
        name: "Bericht ä.txt",
        isDirectory: false,
        isSymlink: true,
        size: 5_000_000_000,
        modified: Date(timeIntervalSince1970: 1_700_000_000.123456789),
        permissions: 0o4755,
        accessed: nil,
        changed: Date(timeIntervalSinceReferenceDate: -12.000_001),
        created: Date(timeIntervalSince1970: 0.5)
    )

    @Test func encodesFrameHeaderBigEndian() {
        let data = LinkFrame(requestID: 0x0102_0304, message: .list("/a")).encoded()
        #expect(Array(data.prefix(9)) == [0, 0, 0, 6, 2, 1, 2, 3, 4])
        #expect(Array(data.dropFirst(9)) == [0, 0, 0, 2, 0x2F, 0x61])
    }

    @Test func roundTripsAllMessages() throws {
        let messages: [LinkMessage] = [
            .hello(version: LinkProtocol.version, name: "Patricks MacBook", writable: false),
            .hello(version: LinkProtocol.version, name: "Patricks iMac", writable: true),
            .list("/Docs"),
            .stat("/Docs/a"),
            .statFollowingLinks("/Docs/b"),
            .readLink("/Docs/c"),
            .openRead("/Docs/d"),
            .read(handle: 7, length: 262_144),
            .close(handle: 7),
            .makeDirectory("/Docs/neu"),
            .removeFile("/Docs/a"),
            .removeDirectory("/Docs/neu"),
            .rename("/Docs/a", "/Docs/b"),
            .makeSymlink("/Docs/l", target: "../x"),
            .setModified("/Docs/a", Date(timeIntervalSince1970: 1.25)),
            .setPermissions("/Docs/a", 0o600),
            .openWrite("/Docs/a", permissions: 0o644),
            .write(handle: 4, data: Data([9, 8, 7])),
            .write(handle: 4, data: Data(count: LinkProtocol.maximumBlock)),
            .write(handle: 4, data: Data()),
            .finish(handle: 4),
            .abort(handle: 5),
            .trash("/Docs/alt"),
            .entries([entry, FileEntry(name: "Ordner", isDirectory: true)], more: true),
            .entries([], more: false),
            .entry(entry),
            .text("../ziel"),
            .handle(3),
            .data(Data([0, 1, 2, 255])),
            .data(Data()),
            .done,
            .error("Fehler"),
        ]
        let frames = messages.enumerated().map { LinkFrame(requestID: UInt32($0.offset), message: $0.element) }
        let data = frames.reduce(Data()) { $0 + $1.encoded() }
        #expect(try decodeAll(data) == frames)
    }

    @Test func transfersFileEntryWithoutLoss() throws {
        let frames = try decodeAll(LinkFrame(requestID: 1, message: .entry(entry)).encoded())
        guard case .entry(let decoded) = frames.first?.message else { Issue.record("no entry"); return }
        #expect(decoded == entry)
        #expect(decoded.modified?.timeIntervalSince1970 == entry.modified?.timeIntervalSince1970)
        #expect(decoded.accessed == nil)
        #expect(decoded.created == entry.created)
    }

    @Test func decodesIncrementallyFromTruncatedData() throws {
        let frames = [LinkFrame(requestID: 1, message: .entry(entry)), LinkFrame(requestID: 2, message: .done)]
        let data = frames.reduce(Data()) { $0 + $1.encoded() }
        var decoder = LinkFrameDecoder()
        var decoded: [LinkFrame] = []
        for byte in data {
            decoder.append(Data([byte]))
            while let frame = try decoder.next() { decoded.append(frame) }
        }
        #expect(decoded == frames)
        #expect(try decoder.next() == nil)
    }

    @Test func rejectsTooLargeFrameBeforePayloadArrives() {
        var decoder = LinkFrameDecoder()
        decoder.append(header(length: UInt32(LinkProtocol.maximumPayload + 1), type: 2))
        #expect(throws: LinkProtocolError.tooLarge(LinkProtocol.maximumPayload + 1)) { try decoder.next() }
    }

    @Test func acceptsMaximumPayload() throws {
        let data = LinkFrame(requestID: 1, message: .data(Data(count: LinkProtocol.maximumPayload))).encoded()
        #expect(try decodeAll(data).first?.message == .data(Data(count: LinkProtocol.maximumPayload)))
    }

    @Test func rejectsUnknownType() {
        #expect(throws: LinkProtocolError.unknownType(200)) { try decodeAll(header(length: 0, type: 200)) }
    }

    @Test func rejectsMalformedPayload() {
        #expect(throws: LinkProtocolError.malformed) { try decodeAll(header(length: 2, type: 2) + Data([0, 0])) }
        #expect(throws: LinkProtocolError.malformed) { try decodeAll(header(length: 1, type: 69) + Data([0])) }
        #expect(throws: LinkProtocolError.malformed) { try decodeAll(header(length: 5, type: 2) + Data([0, 0, 0, 1, 0xFF])) }
    }

    @Test func splitsLargeListingsBelowPayloadLimit() throws {
        let entries = (0..<20_000).map { FileEntry(name: String(repeating: "x", count: 60) + "\($0)", isDirectory: false, modified: Date()) }
        let batches = LinkMessage.entryBatches(entries)
        #expect(batches.count > 1)
        var collected: [FileEntry] = []
        for (index, batch) in batches.enumerated() {
            let data = LinkFrame(requestID: 1, message: batch).encoded()
            #expect(data.count <= LinkProtocol.maximumPayload + LinkProtocol.headerSize)
            guard case .entries(let part, let more) = try decodeAll(data).first?.message else { Issue.record("no entries"); return }
            #expect(more == (index < batches.count - 1))
            collected += part
        }
        #expect(collected == entries)
    }

    @Test func emptyListingIsSingleFinalBatch() {
        #expect(LinkMessage.entryBatches([]) == [.entries([], more: false)])
    }

    @Test func rejectsWriteBlockAboveMaximum() {
        let data = LinkFrame(requestID: 1, message: .write(handle: 1, data: Data(count: LinkProtocol.maximumBlock + 1))).encoded()
        #expect(throws: LinkProtocolError.malformed) { try decodeAll(data) }
    }

    @Test func helloCarriesWritePermission() throws {
        let writable = LinkFrame(requestID: 0, message: .hello(version: 2, name: "B", writable: true)).encoded()
        let readOnly = LinkFrame(requestID: 0, message: .hello(version: 2, name: "B", writable: false)).encoded()
        #expect(writable.count == readOnly.count + 1)
        #expect(try decodeAll(writable).first?.message == .hello(version: 2, name: "B", writable: true))
        #expect(try decodeAll(readOnly).first?.message == .hello(version: 2, name: "B", writable: false))
    }

    @Test func decodesHelloOfVersionOne() throws {
        var payload = LinkPayloadWriter()
        payload.uint32(1)
        payload.string("Alt")
        let data = header(length: UInt32(payload.data.count), type: 1, requestID: 0) + payload.data
        #expect(LinkFrame(requestID: 0, message: .hello(version: 1, name: "Alt", writable: false)).encoded() == data)
        guard case .hello(let version, "Alt", false) = try decodeAll(data).first?.message else { Issue.record("no hello"); return }
        #expect(throws: FileError.self) { try LinkProtocol.checkVersion(version) }
    }

    @Test func checksProtocolVersion() throws {
        #expect(LinkProtocol.version == 2)
        try LinkProtocol.checkVersion(2)
        for version: UInt32 in [1, 3] {
            do {
                try LinkProtocol.checkVersion(version)
                Issue.record("version \(version) accepted")
            } catch {
                #expect(error.localizedDescription == localized("Die Gegenstelle hat eine andere Version von Moonlight Commander"))
            }
        }
    }
}
