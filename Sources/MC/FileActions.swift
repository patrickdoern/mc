import Foundation

struct FileAction {
    let pattern: String
    let kind: String
    let command: String
}

enum FileActions {
    static var fileURL: URL { URL(fileURLWithPath: NSHomeDirectory() + "/.config/moonlight-commander/ext") }

    static let defaultText = """
    # Muster   Aktion (open, view oder edit)   Befehl
    # Makros: %f Datei, %d Ordner, %s Auswahl. Beispiele:
    # *.pdf    open   open -a Preview %f
    # *.png    view   open -a Preview %f
    # *.md     edit   open -a TextEdit %f
    """

    static func load() -> [FileAction] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#") else { return nil }
            let parts = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 3, ["open", "view", "edit"].contains(parts[1]) else { return nil }
            return FileAction(pattern: parts[0], kind: parts[1], command: parts[2])
        }
    }

    static func command(for name: String, kind: String) -> String? {
        load().first { $0.kind == kind && fnmatch($0.pattern, name, FNM_CASEFOLD) == 0 }?.command
    }
}
