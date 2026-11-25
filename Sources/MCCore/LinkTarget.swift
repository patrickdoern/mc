import Foundation

public struct LinkTarget: Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }

    public static func isLink(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("mc://")
    }

    public static func parse(_ text: String) -> LinkTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard isLink(trimmed) else { return nil }
        var rest = String(trimmed.dropFirst(5))
        if rest.hasSuffix("/") { rest.removeLast() }
        let name = rest.removingPercentEncoding ?? rest
        guard !name.isEmpty else { return nil }
        return LinkTarget(name: name)
    }

    public var displayName: String { "mc://" + name }
}
