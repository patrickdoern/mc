import Foundation

public enum SMBAddressError: LocalizedError, Equatable {
    case invalid(String)
    case passwordInAddress

    public var errorDescription: String? {
        switch self {
        case .invalid(let text): localized("Ungültige SMB-Adresse: %@", text as NSString)
        case .passwordInAddress: localized("Passwörter gehören nicht in die Adresse")
        }
    }
}

public struct SMBTarget: Equatable {
    public static let defaultPort = 445

    public var host: String
    public var port: Int
    public var user: String?
    public var domain: String?
    public var share: String
    public var path: String?

    public init(host: String, port: Int = SMBTarget.defaultPort, user: String? = nil, domain: String? = nil, share: String, path: String? = nil) {
        self.host = host
        self.port = port
        self.user = user
        self.domain = domain
        self.share = share
        self.path = path
    }

    public static func isSMB(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("smb://")
    }

    public static func parse(_ text: String) throws -> SMBTarget {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard isSMB(trimmed) else { throw SMBAddressError.invalid(text) }
        var rest = String(trimmed.dropFirst(6))
        var location = ""
        if let slash = rest.firstIndex(of: "/") {
            location = String(rest[rest.index(after: slash)...])
            rest = String(rest[..<slash])
        }
        var user: String?
        var domain: String?
        if let at = rest.lastIndex(of: "@") {
            let credentials = String(rest[..<at])
            guard !credentials.contains(":") else { throw SMBAddressError.passwordInAddress }
            let parts = credentials.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2 { domain = try decode(parts[0], text) }
            user = try decode(parts[parts.count - 1], text)
            rest = String(rest[rest.index(after: at)...])
        }
        var port = defaultPort
        if let colon = rest.lastIndex(of: ":"), let value = Int(rest[rest.index(after: colon)...]) {
            port = value
            rest = String(rest[..<colon])
        }
        let shareEnd = location.firstIndex(of: "/") ?? location.endIndex
        let share = try decode(String(location[..<shareEnd]), text)
        let path = try decode(String(location[shareEnd...]), text)
        let host = try decode(rest, text)
        guard !host.isEmpty, !share.isEmpty, user?.isEmpty != true, domain?.isEmpty != true else { throw SMBAddressError.invalid(text) }
        return SMBTarget(host: host, port: port, user: user, domain: domain, share: share, path: path.isEmpty || path == "/" ? nil : path)
    }

    private static func decode(_ part: String, _ text: String) throws -> String {
        guard let decoded = part.removingPercentEncoding else { throw SMBAddressError.invalid(text) }
        return decoded
    }

    public var displayName: String {
        "smb://" + (user.map { $0 + "@" } ?? "") + host + (port == Self.defaultPort ? "" : ":\(port)") + "/" + share
    }

    public var mountURL: URL? {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = host
        if port != Self.defaultPort { components.port = port }
        components.user = user.map { name in domain.map { $0 + ";" + name } ?? name }
        components.path = "/" + share
        return components.url
    }
}
