import Foundation

public struct LinkPairing: Equatable {
    public let fingerprint: Data
    public let name: String
    public let alwaysAllow: Bool
}

public final class LinkPairings: @unchecked Sendable {
    public static let standard = LinkPairings(defaults: .standard)

    private static let key = "linkPairings"

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var all: [LinkPairing] {
        lock.withLock { stored() }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func isKnown(_ fingerprint: Data) -> Bool {
        lock.withLock { stored().contains { $0.fingerprint == fingerprint } }
    }

    public func alwaysAllows(_ fingerprint: Data) -> Bool {
        lock.withLock { stored().contains { $0.fingerprint == fingerprint && $0.alwaysAllow } }
    }

    public func certificateChanged(_ fingerprint: Data, name: String) -> Bool {
        lock.withLock { stored().contains { $0.name == name && $0.fingerprint != fingerprint } }
    }

    public func remember(_ fingerprint: Data, name: String) {
        lock.withLock {
            var pairings = stored()
            let alwaysAllow = pairings.first { $0.fingerprint == fingerprint }?.alwaysAllow ?? false
            pairings.removeAll { $0.fingerprint == fingerprint || $0.name == name }
            pairings.append(LinkPairing(fingerprint: fingerprint, name: name, alwaysAllow: alwaysAllow))
            store(pairings)
        }
    }

    public func setAlwaysAllow(_ alwaysAllow: Bool, for fingerprint: Data) {
        lock.withLock {
            store(stored().map { $0.fingerprint == fingerprint ? LinkPairing(fingerprint: $0.fingerprint, name: $0.name, alwaysAllow: alwaysAllow) : $0 })
        }
    }

    public func forget(_ fingerprint: Data) {
        lock.withLock { store(stored().filter { $0.fingerprint != fingerprint }) }
    }

    private func stored() -> [LinkPairing] {
        guard let entries = defaults.array(forKey: Self.key) else { return [] }
        return entries.compactMap { entry in
            guard let values = entry as? [String: Any],
                  let hex = values["fingerprint"] as? String,
                  let fingerprint = Self.data(hex: hex),
                  let name = values["name"] as? String
            else { return nil }
            return LinkPairing(fingerprint: fingerprint, name: name, alwaysAllow: values["alwaysAllow"] as? Bool ?? false)
        }
    }

    private func store(_ pairings: [LinkPairing]) {
        defaults.set(pairings.map { ["fingerprint": Self.hex($0.fingerprint), "name": $0.name, "alwaysAllow": $0.alwaysAllow] as [String: Any] }, forKey: Self.key)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func data(hex: String) -> Data? {
        guard !hex.isEmpty, hex.allSatisfy(\.isHexDigit) else { return nil }
        let characters = Array(hex.utf8)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(decoding: characters[index ..< index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        return Data(bytes)
    }
}
