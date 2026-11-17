import Foundation

enum Formatting {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy HH:mm"
        return formatter
    }()

    static func date(_ date: Date?) -> String {
        date.map(dateFormatter.string(from:)) ?? ""
    }

    static func size(_ bytes: Int64) -> String {
        guard bytes >= 100_000 else { return String(bytes) }
        let units = ["K", "M", "G", "T"]
        var value = Double(bytes) / 1024
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return String(format: value < 10 ? "%.1f%@" : "%.0f%@", value, units[unit])
    }

    static func exactSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func permissions(_ mode: UInt16) -> String {
        let symbols = Array("rwxrwxrwx")
        return String((0..<9).map { mode & (1 << UInt16(8 - $0)) != 0 ? symbols[$0] : "-" })
    }
}
