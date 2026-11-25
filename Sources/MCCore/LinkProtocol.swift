import Foundation

public enum LinkProtocol {
    public static let version: UInt32 = 3
    public static let maximumPayload = 1024 * 1024
    public static let maximumBlock = 256 * 1024
    public static let serviceType = "_mc-link._tcp"
    static let headerSize = 9
    static let pairingTimeout: TimeInterval = 60

    public static func checkVersion(_ version: UInt32) throws {
        guard version == Self.version else { throw FileError(localized("Die Gegenstelle hat eine andere Version von Moonlight Commander")) }
    }
}

public enum LinkProtocolError: Error, Equatable {
    case tooLarge(Int)
    case unknownType(UInt8)
    case malformed
}

public enum LinkMessage: Equatable {
    case hello(version: UInt32, name: String, writable: Bool, knowsPeer: Bool)
    case list(String)
    case stat(String)
    case statFollowingLinks(String)
    case readLink(String)
    case openRead(String)
    case read(handle: UInt32, length: UInt32)
    case close(handle: UInt32)
    case makeDirectory(String)
    case removeFile(String)
    case removeDirectory(String)
    case rename(String, String)
    case makeSymlink(String, target: String)
    case setModified(String, Date)
    case setPermissions(String, UInt16)
    case openWrite(String, permissions: UInt16)
    case write(handle: UInt32, data: Data)
    case finish(handle: UInt32)
    case abort(handle: UInt32)
    case trash(String)
    case entries([FileEntry], more: Bool)
    case entry(FileEntry)
    case text(String)
    case handle(UInt32)
    case data(Data)
    case done
    case error(String)

    var isError: Bool {
        guard case .error = self else { return false }
        return true
    }

    public static func entryBatches(_ entries: [FileEntry]) -> [LinkMessage] {
        var batches: [LinkMessage] = []
        var batch: [FileEntry] = []
        var size = 5
        for entry in entries {
            var writer = LinkPayloadWriter()
            writer.entry(entry)
            if size + writer.data.count > LinkProtocol.maximumPayload {
                batches.append(.entries(batch, more: true))
                batch = []
                size = 5
            }
            batch.append(entry)
            size += writer.data.count
        }
        return batches + [.entries(batch, more: false)]
    }
}

private enum LinkMessageType: UInt8 {
    case hello = 1
    case list
    case stat
    case statFollowingLinks
    case readLink
    case openRead
    case read
    case close
    case makeDirectory
    case removeFile
    case removeDirectory
    case rename
    case makeSymlink
    case setModified
    case setPermissions
    case openWrite
    case write
    case finish
    case abort
    case trash
    case entries = 64
    case entry
    case text
    case handle
    case data
    case done
    case error
}

public struct LinkFrame: Equatable {
    public let requestID: UInt32
    public let message: LinkMessage

    public init(requestID: UInt32, message: LinkMessage) {
        self.requestID = requestID
        self.message = message
    }

    public func encoded() -> Data {
        var payload = LinkPayloadWriter()
        let type: LinkMessageType
        switch message {
        case .hello(let version, let name, let writable, let knowsPeer):
            type = .hello
            payload.uint32(version)
            payload.string(name)
            let flags: UInt8 = (writable ? 1 : 0) | (knowsPeer ? 2 : 0)
            if flags != 0 { payload.byte(flags) }
        case .list(let path):
            type = .list
            payload.string(path)
        case .stat(let path):
            type = .stat
            payload.string(path)
        case .statFollowingLinks(let path):
            type = .statFollowingLinks
            payload.string(path)
        case .readLink(let path):
            type = .readLink
            payload.string(path)
        case .openRead(let path):
            type = .openRead
            payload.string(path)
        case .read(let handle, let length):
            type = .read
            payload.uint32(handle)
            payload.uint32(length)
        case .close(let handle):
            type = .close
            payload.uint32(handle)
        case .makeDirectory(let path):
            type = .makeDirectory
            payload.string(path)
        case .removeFile(let path):
            type = .removeFile
            payload.string(path)
        case .removeDirectory(let path):
            type = .removeDirectory
            payload.string(path)
        case .rename(let from, let to):
            type = .rename
            payload.string(from)
            payload.string(to)
        case .makeSymlink(let path, let target):
            type = .makeSymlink
            payload.string(path)
            payload.string(target)
        case .setModified(let path, let date):
            type = .setModified
            payload.string(path)
            payload.date(date)
        case .setPermissions(let path, let mode):
            type = .setPermissions
            payload.string(path)
            payload.uint16(mode)
        case .openWrite(let path, let permissions):
            type = .openWrite
            payload.string(path)
            payload.uint16(permissions)
        case .write(let handle, let data):
            type = .write
            payload.uint32(handle)
            payload.data.append(data)
        case .finish(let handle):
            type = .finish
            payload.uint32(handle)
        case .abort(let handle):
            type = .abort
            payload.uint32(handle)
        case .trash(let path):
            type = .trash
            payload.string(path)
        case .entries(let entries, let more):
            type = .entries
            payload.byte(more ? 1 : 0)
            payload.uint32(UInt32(entries.count))
            entries.forEach { payload.entry($0) }
        case .entry(let entry):
            type = .entry
            payload.entry(entry)
        case .text(let text):
            type = .text
            payload.string(text)
        case .handle(let handle):
            type = .handle
            payload.uint32(handle)
        case .data(let data):
            type = .data
            payload.data.append(data)
        case .done:
            type = .done
        case .error(let text):
            type = .error
            payload.string(text)
        }
        var frame = LinkPayloadWriter()
        frame.uint32(UInt32(payload.data.count))
        frame.byte(type.rawValue)
        frame.uint32(requestID)
        return frame.data + payload.data
    }

    static func decode(type rawType: UInt8, requestID: UInt32, payload: [UInt8]) throws -> LinkFrame {
        guard let type = LinkMessageType(rawValue: rawType) else { throw LinkProtocolError.unknownType(rawType) }
        var reader = LinkPayloadReader(payload)
        let message: LinkMessage
        switch type {
        case .hello:
            let version = try reader.uint32()
            let name = try reader.string()
            let flags = try reader.isAtEnd ? 0 : reader.byte()
            message = .hello(version: version, name: name, writable: flags & 1 != 0, knowsPeer: flags & 2 != 0)
        case .list: message = .list(try reader.string())
        case .stat: message = .stat(try reader.string())
        case .statFollowingLinks: message = .statFollowingLinks(try reader.string())
        case .readLink: message = .readLink(try reader.string())
        case .openRead: message = .openRead(try reader.string())
        case .read: message = .read(handle: try reader.uint32(), length: try reader.uint32())
        case .close: message = .close(handle: try reader.uint32())
        case .makeDirectory: message = .makeDirectory(try reader.string())
        case .removeFile: message = .removeFile(try reader.string())
        case .removeDirectory: message = .removeDirectory(try reader.string())
        case .rename: message = .rename(try reader.string(), try reader.string())
        case .makeSymlink: message = .makeSymlink(try reader.string(), target: try reader.string())
        case .setModified: message = .setModified(try reader.string(), try reader.date())
        case .setPermissions: message = .setPermissions(try reader.string(), try reader.uint16())
        case .openWrite: message = .openWrite(try reader.string(), permissions: try reader.uint16())
        case .write:
            let handle = try reader.uint32()
            let data = reader.rest()
            guard data.count <= LinkProtocol.maximumBlock else { throw LinkProtocolError.malformed }
            message = .write(handle: handle, data: data)
        case .finish: message = .finish(handle: try reader.uint32())
        case .abort: message = .abort(handle: try reader.uint32())
        case .trash: message = .trash(try reader.string())
        case .entries:
            let more = try reader.byte() != 0
            let count = try reader.uint32()
            var entries: [FileEntry] = []
            for _ in 0..<count { entries.append(try reader.entry()) }
            message = .entries(entries, more: more)
        case .entry: message = .entry(try reader.entry())
        case .text: message = .text(try reader.string())
        case .handle: message = .handle(try reader.uint32())
        case .data: message = .data(reader.rest())
        case .done: message = .done
        case .error: message = .error(try reader.string())
        }
        try reader.finish()
        return LinkFrame(requestID: requestID, message: message)
    }
}

public struct LinkFrameDecoder {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(contentsOf: data)
    }

    public mutating func next() throws -> LinkFrame? {
        guard buffer.count >= 4 else { return nil }
        var header = LinkPayloadReader(Array(buffer.prefix(LinkProtocol.headerSize)))
        let length = Int(try header.uint32())
        guard length <= LinkProtocol.maximumPayload else { throw LinkProtocolError.tooLarge(length) }
        guard buffer.count >= LinkProtocol.headerSize + length else { return nil }
        let type = try header.byte()
        let requestID = try header.uint32()
        let payload = Array(buffer[LinkProtocol.headerSize..<LinkProtocol.headerSize + length])
        buffer.removeFirst(LinkProtocol.headerSize + length)
        return try LinkFrame.decode(type: type, requestID: requestID, payload: payload)
    }
}

struct LinkPayloadWriter {
    var data = Data()

    mutating func byte(_ value: UInt8) {
        data.append(value)
    }

    mutating func uint16(_ value: UInt16) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func uint32(_ value: UInt32) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func uint64(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func string(_ value: String) {
        let bytes = Array(value.utf8)
        uint32(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    mutating func date(_ value: Date) {
        uint64(value.timeIntervalSinceReferenceDate.bitPattern)
    }

    mutating func optionalDate(_ value: Date?) {
        guard let value else { return byte(0) }
        byte(1)
        date(value)
    }

    mutating func entry(_ entry: FileEntry) {
        string(entry.name)
        byte((entry.isDirectory ? 1 : 0) | (entry.isSymlink ? 2 : 0))
        uint64(UInt64(bitPattern: entry.size))
        uint16(entry.permissions)
        optionalDate(entry.modified)
        optionalDate(entry.accessed)
        optionalDate(entry.changed)
        optionalDate(entry.created)
    }
}

struct LinkPayloadReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func byte() throws -> UInt8 {
        let slice = try take(1)
        return slice[slice.startIndex]
    }

    mutating func uint16() throws -> UInt16 {
        UInt16(try integer(2))
    }

    mutating func uint32() throws -> UInt32 {
        UInt32(try integer(4))
    }

    mutating func uint64() throws -> UInt64 {
        try integer(8)
    }

    mutating func string() throws -> String {
        let count = Int(try uint32())
        guard let text = String(bytes: try take(count), encoding: .utf8) else { throw LinkProtocolError.malformed }
        return text
    }

    mutating func date() throws -> Date {
        Date(timeIntervalSinceReferenceDate: Double(bitPattern: try uint64()))
    }

    mutating func optionalDate() throws -> Date? {
        try byte() == 0 ? nil : try date()
    }

    mutating func entry() throws -> FileEntry {
        let name = try string()
        let flags = try byte()
        let size = Int64(bitPattern: try uint64())
        let permissions = try uint16()
        return FileEntry(
            name: name,
            isDirectory: flags & 1 != 0,
            isSymlink: flags & 2 != 0,
            size: size,
            modified: try optionalDate(),
            permissions: permissions,
            accessed: try optionalDate(),
            changed: try optionalDate(),
            created: try optionalDate()
        )
    }

    var isAtEnd: Bool { offset == bytes.count }

    mutating func rest() -> Data {
        defer { offset = bytes.count }
        return Data(bytes[offset...])
    }

    func finish() throws {
        guard isAtEnd else { throw LinkProtocolError.malformed }
    }

    private mutating func integer(_ count: Int) throws -> UInt64 {
        try take(count).reduce(0) { $0 << 8 | UInt64($1) }
    }

    private mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count <= bytes.count - offset else { throw LinkProtocolError.malformed }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }
}
