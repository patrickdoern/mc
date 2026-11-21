public enum AppLanguagePreference: Equatable, CaseIterable {
    case automatic
    case german
    case english

    public init(stored: [String]?) {
        switch stored?.first.flatMap(Localization.languageCode(of:)) {
        case "de": self = .german
        case "en": self = .english
        default: self = .automatic
        }
    }

    public var stored: [String]? {
        switch self {
        case .automatic: nil
        case .german: ["de"]
        case .english: ["en"]
        }
    }
}
