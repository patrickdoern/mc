import Foundation

public struct FTPTarget: Equatable {
    public var secure: Bool
    public var host: String
    public var port: Int
    public var user: String
    public var path: String?

    public static func isFTP(_ text: String) -> Bool {
        let lower = text.trimmingCharacters(in: .whitespaces).lowercased()
        return lower.hasPrefix("ftp://") || lower.hasPrefix("ftps://")
    }

    /// `ftp://[user[:passwort]@]host[:port][/pfad]` und `ftps://…` (implizites TLS). Ohne Nutzer wird anonym angemeldet.
    public static func parse(_ text: String) -> FTPTarget? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let secure = lower.hasPrefix("ftps://")
        guard secure || lower.hasPrefix("ftp://") else { return nil }
        var rest = String(trimmed.dropFirst(secure ? 7 : 6))
        var path: String?
        if let slash = rest.firstIndex(of: "/") {
            path = String(rest[slash...])
            rest = String(rest[..<slash])
        }
        var user = "anonymous"
        if let at = rest.lastIndex(of: "@") {
            let credentials = String(rest[..<at])
            user = String(credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            rest = String(rest[rest.index(after: at)...])
        }
        var port = secure ? 990 : 21
        if let colon = rest.lastIndex(of: ":"), let value = Int(rest[rest.index(after: colon)...]) {
            port = value
            rest = String(rest[..<colon])
        }
        guard !rest.isEmpty, !user.isEmpty else { return nil }
        return FTPTarget(secure: secure, host: rest, port: port, user: user, path: path?.removingPercentEncoding ?? path)
    }

    public var displayName: String { "\(secure ? "ftps" : "ftp")://\(user)@\(host):\(port)" }
}
