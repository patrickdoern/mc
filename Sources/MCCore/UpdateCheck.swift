import Foundation

public struct AppVersion: Comparable {
    public let components: [Int]

    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) && part.allSatisfy(\.isNumber) ? Int(part) : nil }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

public struct ReleaseInfo: Equatable {
    public let tag: String
    public let url: URL

    public init(tag: String, url: URL) {
        self.tag = tag
        self.url = url
    }
}

public enum UpdateStatus: Equatable {
    case newer(ReleaseInfo)
    case upToDate
}

public enum UpdateCheck {
    public static let endpoint = URL(string: "https://api.github.com/repos/patrickdoern/mc/releases/latest")!

    public typealias Transport = (URLRequest) async throws -> (Data, URLResponse)

    private struct Response: Decodable {
        let tag_name: String?
        let html_url: String?
        let prerelease: Bool?
        let draft: Bool?
    }

    public static func request(installedVersion: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Moonlight-Commander/\(installedVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.prerelease != true, response.draft != true,
              let tag = response.tag_name, let link = response.html_url, let url = URL(string: link)
        else { return nil }
        return ReleaseInfo(tag: tag, url: url)
    }

    public static func status(of data: Data, installedVersion: String) -> UpdateStatus {
        guard let installed = AppVersion(installedVersion),
              let release = parseRelease(data),
              let latest = AppVersion(release.tag),
              latest > installed
        else { return .upToDate }
        return .newer(release)
    }

    public static func check(
        installedVersion: String,
        transport: Transport = { try await URLSession.shared.data(for: $0) }
    ) async throws -> UpdateStatus {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request(installedVersion: installedVersion))
        } catch {
            throw FileError(localized("Update-Prüfung fehlgeschlagen: %@", error.localizedDescription as NSString))
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FileError(localized("Update-Prüfung fehlgeschlagen: GitHub antwortet mit Status %ld", http.statusCode))
        }
        return status(of: data, installedVersion: installedVersion)
    }
}
