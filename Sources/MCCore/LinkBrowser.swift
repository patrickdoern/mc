import Foundation
import Network

public final class LinkBrowser {
    private let browser = NWBrowser(for: .bonjour(type: LinkProtocol.serviceType, domain: nil), using: .tcp)

    public init(onChange: @escaping ([String]) -> Void) {
        browser.browseResultsChangedHandler = { results, _ in
            let names = results.compactMap { result -> String? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return name
            }
            onChange(Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        }
    }

    public func start() {
        browser.start(queue: .main)
    }

    public func stop() {
        browser.cancel()
    }
}
