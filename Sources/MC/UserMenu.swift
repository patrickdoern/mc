import Foundation

struct UserMenuEntry {
    let key: String
    let title: String
    let script: String
}

struct UserMenuContext {
    let currentName: String
    let directory: String
    let selection: [String]
    let otherDirectory: String
    let otherName: String
}

enum UserMenu {
    static var fileURL: URL { URL(fileURLWithPath: NSHomeDirectory() + "/.config/macos-commander/menu") }

    static let defaultText = """
    o   Mit Standardprogramm öffnen
            open %f

    r   Im Finder zeigen
            open -R %f

    t   Terminal hier öffnen
            open -a Terminal %d

    z   Auswahl als tar.gz packen
            tar czf archiv.tar.gz %s

    u   Archiv entpacken
            tar xf %f

    s   Größe der Auswahl (du -sh)
            du -sh %s
    """

    static func load() -> [UserMenuEntry] {
        parse((try? String(contentsOf: fileURL, encoding: .utf8)) ?? defaultText)
    }

    static func parse(_ text: String) -> [UserMenuEntry] {
        var entries: [UserMenuEntry] = []
        var header: (key: String, title: String)?
        var script: [String] = []
        func flush() {
            if let header { entries.append(UserMenuEntry(key: header.key, title: header.title, script: script.joined(separator: "\n"))) }
            script = []
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            guard let first = line.first else { continue }
            if first == "#" || first == "+" || first == "=" { continue }
            if first.isWhitespace {
                script.append(line.trimmingCharacters(in: .whitespaces))
            } else {
                flush()
                header = (String(first), line.dropFirst().trimmingCharacters(in: .whitespaces))
            }
        }
        flush()
        return entries.filter { !$0.script.isEmpty }
    }

    static func expand(_ script: String, context: UserMenuContext) -> String {
        var result = ""
        var iterator = script.makeIterator()
        while let character = iterator.next() {
            guard character == "%" else {
                result.append(character)
                continue
            }
            switch iterator.next() {
            case "f": result += Shell.quote(context.currentName)
            case "d": result += Shell.quote(context.directory)
            case "s": result += context.selection.map(Shell.quote).joined(separator: " ")
            case "D": result += Shell.quote(context.otherDirectory)
            case "F": result += Shell.quote(context.otherName)
            case "%": result.append("%")
            case let other?: result += "%" + String(other)
            case nil: result.append("%")
            }
        }
        return result
    }
}
