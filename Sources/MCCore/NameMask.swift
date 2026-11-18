import Foundation

public enum NameMask {
    public static func isMask(_ name: String) -> Bool {
        name.contains("*")
    }

    public static func apply(_ mask: String, to name: String) -> String {
        guard let dot = mask.lastIndex(of: ".") else { return mask.replacingOccurrences(of: "*", with: name) }
        let maskName = String(mask[..<dot])
        let maskExtension = String(mask[mask.index(after: dot)...])
        guard let nameDot = name.lastIndex(of: "."), nameDot != name.startIndex else {
            let stem = maskName.replacingOccurrences(of: "*", with: name)
            return maskExtension == "*" || maskExtension.isEmpty ? stem : stem + "." + maskExtension.replacingOccurrences(of: "*", with: "")
        }
        let stem = String(name[..<nameDot])
        let fileExtension = String(name[name.index(after: nameDot)...])
        return maskName.replacingOccurrences(of: "*", with: stem) + "." + maskExtension.replacingOccurrences(of: "*", with: fileExtension)
    }
}
