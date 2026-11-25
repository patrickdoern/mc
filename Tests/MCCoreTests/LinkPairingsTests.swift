import Foundation
import Testing
@testable import MCCore

private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
    let suite = "digital.doern.mc.tests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
}

private let first = Data(repeating: 0xA1, count: 32)
private let second = Data(repeating: 0x0B, count: 32)

struct LinkPairingsTests {
    @Test func unknownFingerprintIsNotKnown() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            #expect(!pairings.isKnown(first))
            #expect(!pairings.alwaysAllows(first))
            #expect(pairings.all.isEmpty)
        }
    }

    @Test func rememberStoresFingerprintAndNameWithoutAlwaysAllow() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "Büro-Mac")
            #expect(pairings.isKnown(first))
            #expect(!pairings.isKnown(second))
            #expect(!pairings.alwaysAllows(first))
            #expect(pairings.all == [LinkPairing(fingerprint: first, name: "Büro-Mac", alwaysAllow: false)])
        }
    }

    @Test func rememberUpdatesNameAndKeepsAlwaysAllow() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "Alt")
            pairings.setAlwaysAllow(true, for: first)
            pairings.remember(first, name: "Neu")
            #expect(pairings.all == [LinkPairing(fingerprint: first, name: "Neu", alwaysAllow: true)])
        }
    }

    @Test func alwaysAllowCanBeSetAndWithdrawn() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "A")
            pairings.remember(second, name: "B")
            pairings.setAlwaysAllow(true, for: first)
            #expect(pairings.alwaysAllows(first))
            #expect(!pairings.alwaysAllows(second))
            pairings.setAlwaysAllow(false, for: first)
            #expect(!pairings.alwaysAllows(first))
            #expect(pairings.isKnown(first))
        }
    }

    @Test func alwaysAllowForUnknownFingerprintChangesNothing() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.setAlwaysAllow(true, for: first)
            #expect(!pairings.isKnown(first))
            #expect(pairings.all.isEmpty)
        }
    }

    @Test func forgetRemovesOnlyThatMac() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "A")
            pairings.remember(second, name: "B")
            pairings.forget(first)
            #expect(!pairings.isKnown(first))
            #expect(pairings.isKnown(second))
        }
    }

    @Test func changedFingerprintForKnownNameIsDetectedAndReplacedOnRemember() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "Studio")
            pairings.setAlwaysAllow(true, for: first)
            #expect(pairings.certificateChanged(second, name: "Studio"))
            #expect(!pairings.certificateChanged(first, name: "Studio"))
            #expect(!pairings.certificateChanged(second, name: "Anderer"))
            pairings.remember(second, name: "Studio")
            #expect(!pairings.isKnown(first))
            #expect(pairings.all == [LinkPairing(fingerprint: second, name: "Studio", alwaysAllow: false)])
            #expect(!pairings.certificateChanged(second, name: "Studio"))
        }
    }

    @Test func allIsSortedByName() throws {
        try withDefaults { defaults in
            let pairings = LinkPairings(defaults: defaults)
            pairings.remember(first, name: "mac 10")
            pairings.remember(second, name: "Mac 2")
            #expect(pairings.all.map(\.name) == ["Mac 2", "mac 10"])
        }
    }

    @Test func pairingsPersistInDefaults() throws {
        try withDefaults { defaults in
            LinkPairings(defaults: defaults).remember(first, name: "A")
            LinkPairings(defaults: defaults).setAlwaysAllow(true, for: first)
            let reloaded = LinkPairings(defaults: defaults)
            #expect(reloaded.all == [LinkPairing(fingerprint: first, name: "A", alwaysAllow: true)])
            let stored = try #require(defaults.array(forKey: "linkPairings") as? [[String: Any]])
            #expect(stored.first?["fingerprint"] as? String == String(repeating: "a1", count: 32))
        }
    }

    @Test func damagedEntriesAreIgnored() throws {
        try withDefaults { defaults in
            defaults.set([
                "kein Eintrag",
                ["fingerprint": "zz", "name": "Kaputt"],
                ["fingerprint": "abc", "name": "Ungerade"],
                ["fingerprint": "+a", "name": "Vorzeichen"],
                ["fingerprint": "", "name": "Leer"],
                ["name": "Ohne Fingerabdruck"],
                ["fingerprint": "0b0b", "name": 42],
                ["fingerprint": "0b0b", "name": "Gut", "alwaysAllow": "ja"],
            ] as [Any], forKey: "linkPairings")
            let pairings = LinkPairings(defaults: defaults)
            #expect(pairings.all == [LinkPairing(fingerprint: Data([0x0B, 0x0B]), name: "Gut", alwaysAllow: false)])
        }
    }

    @Test func damagedValueTypeIsIgnored() throws {
        try withDefaults { defaults in
            defaults.set("kaputt", forKey: "linkPairings")
            let pairings = LinkPairings(defaults: defaults)
            #expect(pairings.all.isEmpty)
            pairings.remember(first, name: "A")
            #expect(pairings.isKnown(first))
        }
    }
}
