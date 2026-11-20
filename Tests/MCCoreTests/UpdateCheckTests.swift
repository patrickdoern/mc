import Foundation
import Testing
@testable import MCCore

private func json(_ text: String) -> Data { Data(text.utf8) }

private let release = """
{"tag_name": "v1.3", "html_url": "https://github.com/patrickdoern/mc/releases/tag/v1.3", "prerelease": false, "draft": false, "body": "Notizen"}
"""

@Suite struct UpdateCheckTests {
    @Test func comparesNumericallyPerSegment() throws {
        #expect(try #require(AppVersion("1.10")) > #require(AppVersion("1.9")))
        #expect(try #require(AppVersion("2.0")) > #require(AppVersion("1.99.99")))
        #expect(try #require(AppVersion("1.2.1")) > #require(AppVersion("1.2")))
    }

    @Test func ignoresLeadingVAndTrailingZeros() throws {
        #expect(try #require(AppVersion("v1.2")) == #require(AppVersion("1.2.0")))
        #expect(try #require(AppVersion("V1.2")) == #require(AppVersion("1.2")))
    }

    @Test func rejectsGarbageTags() {
        for text in ["", "v", "latest", "1.x", "1..2", "1.2-beta", "1.2.", "-1"] {
            #expect(AppVersion(text) == nil)
        }
    }

    @Test func parsesRelease() throws {
        let info = try #require(UpdateCheck.parseRelease(json(release)))
        #expect(info.tag == "v1.3")
        #expect(info.url.absoluteString == "https://github.com/patrickdoern/mc/releases/tag/v1.3")
    }

    @Test func ignoresPrereleaseAndDraft() {
        let prerelease = #"{"tag_name": "v2.0", "html_url": "https://example.com", "prerelease": true, "draft": false}"#
        let draft = #"{"tag_name": "v2.0", "html_url": "https://example.com", "prerelease": false, "draft": true}"#
        #expect(UpdateCheck.parseRelease(json(prerelease)) == nil)
        #expect(UpdateCheck.parseRelease(json(draft)) == nil)
    }

    @Test func ignoresIncompleteOrInvalidResponses() {
        #expect(UpdateCheck.parseRelease(json(#"{"html_url": "https://example.com"}"#)) == nil)
        #expect(UpdateCheck.parseRelease(json(#"{"tag_name": "v1.3"}"#)) == nil)
        #expect(UpdateCheck.parseRelease(json(#"{"message": "Not Found"}"#)) == nil)
        #expect(UpdateCheck.parseRelease(json("kein json")) == nil)
    }

    @Test func reportsNewerRelease() throws {
        let status = UpdateCheck.status(of: json(release), installedVersion: "1.2")
        let info = try #require(UpdateCheck.parseRelease(json(release)))
        #expect(status == .newer(info))
    }

    @Test func reportsUpToDate() {
        #expect(UpdateCheck.status(of: json(release), installedVersion: "1.3") == .upToDate)
        #expect(UpdateCheck.status(of: json(release), installedVersion: "1.3.0") == .upToDate)
        #expect(UpdateCheck.status(of: json(release), installedVersion: "1.4") == .upToDate)
        #expect(UpdateCheck.status(of: json(release), installedVersion: "unbekannt") == .upToDate)
    }

    @Test func treatsGarbageTagAsUpToDate() {
        let garbage = #"{"tag_name": "nightly", "html_url": "https://example.com"}"#
        #expect(UpdateCheck.status(of: json(garbage), installedVersion: "1.2") == .upToDate)
    }

    @Test func buildsRequest() {
        let request = UpdateCheck.request(installedVersion: "1.2")
        #expect(request.url == UpdateCheck.endpoint)
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Moonlight-Commander/1.2")
        #expect(request.allHTTPHeaderFields?.count == 2)
    }

    @Test func checkUsesTransport() async throws {
        let status = try await UpdateCheck.check(installedVersion: "1.2") { request in
            (json(release), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        guard case .newer(let info) = status else { Issue.record("Erwartet: neuere Version"); return }
        #expect(info.tag == "v1.3")
    }

    @Test func checkReportsHTTPFailure() async {
        await #expect(throws: FileError.self) {
            try await UpdateCheck.check(installedVersion: "1.2") { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
            }
        }
    }

    @Test func checkReportsNetworkFailure() async {
        await #expect(throws: FileError.self) {
            try await UpdateCheck.check(installedVersion: "1.2") { _ in throw URLError(.notConnectedToInternet) }
        }
    }
}
