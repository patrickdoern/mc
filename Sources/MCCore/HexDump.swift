import Foundation

public enum HexDump {
    private static let digits = Array("0123456789abcdef".utf8)

    public static func render(_ data: Data, limit: Int = 4_000_000) -> String {
        let shown = min(data.count, limit)
        var output: [UInt8] = []
        output.reserveCapacity(shown / 16 * 78 + 80)
        var offset = 0
        while offset < shown {
            let end = min(offset + 16, shown)
            for shift in stride(from: 28, through: 0, by: -4) { output.append(digits[(offset >> shift) & 0xF]) }
            output.append(contentsOf: [0x20, 0x20])
            for index in offset..<offset + 16 {
                if index < end {
                    output.append(digits[Int(data[data.startIndex + index] >> 4)])
                    output.append(digits[Int(data[data.startIndex + index] & 0xF)])
                } else {
                    output.append(contentsOf: [0x20, 0x20])
                }
                output.append(0x20)
                if index == offset + 7 { output.append(0x20) }
            }
            output.append(contentsOf: [0x20, 0x7C])
            for index in offset..<end {
                let byte = data[data.startIndex + index]
                output.append(byte >= 0x20 && byte < 0x7F ? byte : 0x2E)
            }
            output.append(contentsOf: [0x7C, 0x0A])
            offset = end
        }
        var text = String(decoding: output, as: UTF8.self)
        if shown < data.count { text += "… (gekürzt: \(shown) von \(data.count) Bytes)\n" }
        return text
    }
}
