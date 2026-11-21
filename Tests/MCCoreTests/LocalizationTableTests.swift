import Foundation
import Testing

enum LocalizationAudit {
    static func check(sources: [(name: String, text: String)], table: String) -> [String] {
        var problems: [String] = []
        var used: Set<String> = []
        for source in sources {
            let (keys, errors) = usedKeys(in: source.text)
            used.formUnion(keys)
            problems += errors.map { "\(source.name): \($0)" }
        }
        let (entries, tableErrors) = parseTable(table)
        problems += tableErrors
        for key in used.sorted() where !entries.contains(where: { $0.key == key }) {
            problems.append("missing in table: \(key)")
        }
        for entry in entries {
            if !used.contains(entry.key) { problems.append("unused key: \(entry.key)") }
            if entry.value.isEmpty { problems.append("empty translation: \(entry.key)") }
            else if placeholders(entry.key) != placeholders(entry.value) { problems.append("placeholder mismatch: \(entry.key)") }
        }
        return problems
    }

    static func usedKeys(in text: String) -> (keys: Set<String>, errors: [String]) {
        var keys: Set<String> = []
        var errors: [String] = []
        let characters = Array(text)
        let marker = Array("localized(")
        var index = 0
        while index + marker.count <= characters.count {
            guard Array(characters[index..<index + marker.count]) == marker,
                  index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber || characters[index - 1] == "_" || characters[index - 1] == ".")
            else { index += 1; continue }
            let line = characters[..<index].filter { $0 == "\n" }.count + 1
            var position = index + marker.count
            while position < characters.count, characters[position] == " " { position += 1 }
            var literal = ""
            var closed = false
            var interpolated = false
            if position < characters.count, characters[position] == "\"" {
                position += 1
                while position < characters.count, characters[position] != "\n" {
                    let character = characters[position]
                    if character == "\\" {
                        if position + 1 < characters.count, characters[position + 1] == "(" { interpolated = true }
                        literal.append(character)
                        if position + 1 < characters.count { literal.append(characters[position + 1]) }
                        position += 2
                        continue
                    }
                    if character == "\"" { closed = true; position += 1; break }
                    literal.append(character)
                    position += 1
                }
            }
            while position < characters.count, characters[position] == " " { position += 1 }
            let terminated = position < characters.count && (characters[position] == "," || characters[position] == ")")
            if closed && !interpolated && terminated {
                keys.insert(unescape(literal))
            } else {
                errors.append("line \(line): localized( needs a single-line string literal without interpolation")
            }
            index = max(position, index + 1)
        }
        return (keys, errors)
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var escaped = false
        for character in text {
            if escaped {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func parseTable(_ text: String) -> (entries: [(key: String, value: String)], errors: [String]) {
        let pattern = try! NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$"#)
        var entries: [(key: String, value: String)] = []
        var errors: [String] = []
        var seen: Set<String> = []
        for (offset, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") || (trimmed.hasPrefix("/*") && trimmed.hasSuffix("*/")) { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = pattern.firstMatch(in: trimmed, range: range),
                  let keyRange = Range(match.range(at: 1), in: trimmed),
                  let valueRange = Range(match.range(at: 2), in: trimmed)
            else { errors.append("table line \(offset + 1): invalid"); continue }
            let key = unescape(String(trimmed[keyRange]))
            if !seen.insert(key).inserted { errors.append("duplicate key: \(key)") }
            entries.append((key, unescape(String(trimmed[valueRange]))))
        }
        return (entries, errors)
    }

    static func placeholders(_ text: String) -> [Int: Character] {
        let pattern = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z)?([@dDiuUxXoOfeEgGcCsSp%])"#)
        var result: [Int: Character] = [:]
        var next = 1
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let kindRange = Range(match.range(at: 2), in: text), let kind = text[kindRange].first, kind != "%" else { continue }
            if let positionRange = Range(match.range(at: 1), in: text), let position = Int(text[positionRange]) {
                result[position] = kind
            } else {
                result[next] = kind
                next += 1
            }
        }
        return result
    }
}

@Suite struct LocalizationTableTests {
    @Test func acceptsConsistentTable() {
        let sources = [("a.swift", #"let a = localized("Abbrechen"); let b = localized("%@ nach %d", x, 1)"#)]
        let table = "// Kommentar\n\n\"Abbrechen\" = \"Cancel\";\n\"%@ nach %d\" = \"%2$d from %1$@\";\n"
        #expect(LocalizationAudit.check(sources: sources, table: table).isEmpty)
    }

    @Test func reportsMissingKey() {
        let problems = LocalizationAudit.check(sources: [("a.swift", #"localized("Löschen")"#)], table: "")
        #expect(problems == ["missing in table: Löschen"])
    }

    @Test func reportsUnusedKey() {
        let problems = LocalizationAudit.check(sources: [], table: "\"Löschen\" = \"Delete\";\n")
        #expect(problems == ["unused key: Löschen"])
    }

    @Test func reportsEmptyTranslation() {
        let problems = LocalizationAudit.check(sources: [("a.swift", #"localized("Löschen")"#)], table: "\"Löschen\" = \"\";\n")
        #expect(problems == ["empty translation: Löschen"])
    }

    @Test func reportsPlaceholderMismatch() {
        let sources = [("a.swift", #"localized("%d Dateien", n); localized("%@ kopieren", n)"#)]
        let table = "\"%d Dateien\" = \"%@ files\";\n\"%@ kopieren\" = \"Copy\";\n"
        #expect(LocalizationAudit.check(sources: sources, table: table).count == 2)
    }

    @Test func reportsDuplicateKey() {
        let table = "\"Löschen\" = \"Delete\";\n\"Löschen\" = \"Remove\";\n"
        let problems = LocalizationAudit.check(sources: [("a.swift", #"localized("Löschen")"#)], table: table)
        #expect(problems == ["duplicate key: Löschen"])
    }

    @Test func reportsInvalidTableLine() {
        let problems = LocalizationAudit.check(sources: [], table: "Löschen = Delete\n")
        #expect(problems == ["table line 1: invalid"])
    }

    @Test func reportsInterpolationAndNonLiteralCalls() {
        let sources = [("a.swift", "localized(\"A \\(x)\")\nlocalized(name)\nlocalized(\"A\" + b)")]
        let problems = LocalizationAudit.check(sources: sources, table: "")
        #expect(problems.count == 3)
        #expect(problems.allSatisfy { $0.hasPrefix("a.swift: line") })
    }

    @Test func handlesEscapesAndIgnoresOtherIdentifiers() {
        let sources = [("a.swift", #"isLocalized("x"); localized("Zeile\n\"Zitat\"")"#)]
        let table = #""Zeile\n\"Zitat\"" = "Line\n\"quote\"";"# + "\n"
        #expect(LocalizationAudit.check(sources: sources, table: table).isEmpty)
    }

    @Test func repositoryTableMatchesSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sourcesRoot = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        var sources: [(name: String, text: String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" && url.lastPathComponent != "Localization.swift" {
            sources.append((url.path.replacingOccurrences(of: root.path + "/", with: ""), try String(contentsOf: url, encoding: .utf8)))
        }
        let table = try String(contentsOf: root.appendingPathComponent("Sources/MC/Resources/en.lproj/Localizable.strings"), encoding: .utf8)
        #expect(!sources.isEmpty)
        #expect(LocalizationAudit.check(sources: sources, table: table) == [])
    }
}
