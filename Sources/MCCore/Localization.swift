import Foundation

public func localized(_ key: String, _ arguments: CVarArg...) -> String {
    Localization.shared.text(key, arguments)
}

enum AppLanguage: Equatable {
    case german
    case english
}

struct Localization: Sendable {
    static let shared = Localization(
        language: detectLanguage(Locale.preferredLanguages),
        table: loadEnglishTable(from: .main)
    )

    let language: AppLanguage
    let table: [String: String]

    init(language: AppLanguage, table: [String: String]) {
        self.language = language
        self.table = table
    }

    static func detectLanguage(_ identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first?.lowercased()
            if code == "de" { return .german }
            if code == "en" { return .english }
        }
        return .english
    }

    static func loadEnglishTable(from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"),
              let entries = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return entries
    }

    func text(_ key: String, _ arguments: [CVarArg] = []) -> String {
        let template = language == .german ? key : (table[key].flatMap { $0.isEmpty ? nil : $0 } ?? key)
        return arguments.isEmpty ? template : String(format: template, arguments: arguments)
    }
}
