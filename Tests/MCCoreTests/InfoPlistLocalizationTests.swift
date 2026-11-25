import Foundation
import Testing

enum InfoPlistAudit {
    static func check(keys: [String], table: String) -> [String] {
        var problems: [String] = []
        let (entries, errors) = LocalizationAudit.parseTable(table)
        problems += errors
        for name in keys where !entries.contains(where: { $0.key == name }) {
            problems.append("missing in table: \(name)")
        }
        for entry in entries {
            if !keys.contains(entry.key) { problems.append("unused key: \(entry.key)") }
            if entry.value.isEmpty { problems.append("empty translation: \(entry.key)") }
        }
        return problems
    }
}

@Suite struct InfoPlistLocalizationTests {
    @Test func acceptsConsistentTable() {
        #expect(InfoPlistAudit.check(keys: ["Textdatei", "Ordner"], table: "\"Textdatei\" = \"Text File\";\n\"Ordner\" = \"Folder\";\n").isEmpty)
    }

    @Test func reportsMissingEntry() {
        #expect(InfoPlistAudit.check(keys: ["Textdatei", "Ordner"], table: "\"Textdatei\" = \"Text File\";\n") == ["missing in table: Ordner"])
    }

    @Test func reportsOrphanedEntry() {
        #expect(InfoPlistAudit.check(keys: ["Textdatei"], table: "\"Textdatei\" = \"Text File\";\n\"Bild\" = \"Image\";\n") == ["unused key: Bild"])
    }

    @Test func reportsEmptyTranslation() {
        #expect(InfoPlistAudit.check(keys: ["Textdatei"], table: "\"Textdatei\" = \"\";\n") == ["empty translation: Textdatei"])
    }

    @Test func reportsDuplicateEntry() {
        #expect(InfoPlistAudit.check(keys: ["Textdatei"], table: "\"Textdatei\" = \"Text File\";\n\"Textdatei\" = \"Text\";\n") == ["duplicate key: Textdatei"])
    }

    @Test func repositoryInfoPlistMatchesTable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let names = types.compactMap { $0["CFBundleTypeName"] as? String }
        #expect(names.count == types.count)
        let descriptions = ["NSLocalNetworkUsageDescription"]
        #expect(descriptions.allSatisfy { plist[$0] is String })
        let table = try String(contentsOf: root.appendingPathComponent("Sources/MC/Resources/en.lproj/InfoPlist.strings"), encoding: .utf8)
        #expect(InfoPlistAudit.check(keys: names + descriptions, table: table) == [])
    }
}
