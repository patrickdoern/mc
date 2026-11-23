import Foundation
import Testing
@testable import MCCore

private final class FakeUnmounter: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []
    let busy: Set<String>
    let completes: Bool

    init(busy: Set<String> = [], completes: Bool = true) {
        self.busy = busy
        self.completes = completes
    }

    var unmounted: [String] { lock.withLock { calls } }

    func unmount(_ mountpoint: String, done: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { calls.append(mountpoint) }
        if completes { done(!busy.contains(mountpoint)) }
    }
}

@Suite struct SMBMountsTests {
    private let target = SMBTarget(host: "Server", user: "anna", share: "Daten")

    @Test func findsExistingMountIgnoringUserAndCase() {
        let mounts = [
            SMBMount(source: "//anna@server/other", mountpoint: "/Volumes/other"),
            SMBMount(source: "//bob@SERVER/daten", mountpoint: "/Volumes/daten"),
        ]
        #expect(SMBMounts.existingMountpoint(for: target, in: mounts) == "/Volumes/daten")
    }

    @Test func matchesDomainPortAndPercentEncodedSources() {
        let spaced = SMBTarget(host: "nas", share: "Gemeinsame Dateien")
        #expect(SMBMounts.existingMountpoint(for: spaced, in: [SMBMount(source: "//FIRMA;anna@nas:1445/Gemeinsame%20Dateien", mountpoint: "/Volumes/G")]) == "/Volumes/G")
        let admin = SMBTarget(host: "192.0.2.10", share: "c$")
        #expect(SMBMounts.existingMountpoint(for: admin, in: [SMBMount(source: "//GUEST:@192.0.2.10/C$", mountpoint: "/Volumes/C$")]) == "/Volumes/C$")
    }

    @Test func ignoresOtherHostsSharesAndMalformedSources() {
        let mounts = [
            SMBMount(source: "//anna@server2/Daten", mountpoint: "/Volumes/a"),
            SMBMount(source: "//anna@server/Daten2", mountpoint: "/Volumes/b"),
            SMBMount(source: "//server", mountpoint: "/Volumes/c"),
            SMBMount(source: "server/Daten", mountpoint: "/Volumes/d"),
        ]
        #expect(SMBMounts.existingMountpoint(for: target, in: mounts) == nil)
    }

    @Test func readsOnlySMBMountsFromSystem() {
        #expect(SMBMounts.currentMounts().allSatisfy { $0.source.hasPrefix("//") && $0.mountpoint.hasPrefix("/") })
    }

    @Test func decidesUnusedMountpointsAlongPathBoundaries() {
        let owned: Set<String> = ["/Volumes/a", "/Volumes/ab", "/Volumes/c"]
        #expect(SMBMounts.unused(owned: owned, panelPaths: ["/Volumes/ab/x", "/Users/anna"]) == ["/Volumes/a", "/Volumes/c"])
        #expect(SMBMounts.unused(owned: owned, panelPaths: ["/Volumes/a", "/Volumes/c/d/e"]) == ["/Volumes/ab"])
        #expect(SMBMounts.unused(owned: owned, panelPaths: ["/Volumes"]) == ["/Volumes/a", "/Volumes/ab", "/Volumes/c"])
        #expect(SMBMounts.unused(owned: [], panelPaths: ["/Volumes/a"]) == [])
    }

    @Test func neverReleasesForeignMounts() {
        let fake = FakeUnmounter()
        let mounts = SMBMounts(unmount: fake.unmount)
        mounts.register("/Volumes/eigen")
        mounts.release(keeping: ["/Users/anna"])
        #expect(fake.unmounted == ["/Volumes/eigen"])
        #expect(mounts.ownedMountpoints.isEmpty)
    }

    @Test func keepsBusyMountRegisteredForRetry() {
        let fake = FakeUnmounter(busy: ["/Volumes/belegt"])
        let mounts = SMBMounts(unmount: fake.unmount)
        mounts.register("/Volumes/belegt")
        mounts.release(keeping: [])
        mounts.release(keeping: [])
        #expect(fake.unmounted == ["/Volumes/belegt", "/Volumes/belegt"])
        #expect(mounts.ownedMountpoints == ["/Volumes/belegt"])
    }

    @Test func keepsMountUsedThroughSymlink() throws {
        let base = try #require(LocalFileSystem.shared.canonicalPath(NSTemporaryDirectory()))
        let directory = PosixPath.join(base, "mc-smb-\(UUID().uuidString)")
        let volume = PosixPath.join(directory, "volume")
        let link = PosixPath.join(directory, "link")
        try FileManager.default.createDirectory(atPath: PosixPath.join(volume, "sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: volume)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let fake = FakeUnmounter()
        let mounts = SMBMounts(unmount: fake.unmount)
        mounts.register(volume)
        mounts.release(keeping: [PosixPath.join(link, "sub")])
        #expect(fake.unmounted.isEmpty)
        #expect(mounts.ownedMountpoints == [volume])
    }

    @Test func releaseAllWaitsAtMostTimeout() {
        let fake = FakeUnmounter(completes: false)
        let mounts = SMBMounts(unmount: fake.unmount)
        mounts.register("/Volumes/a")
        mounts.register("/Volumes/b")
        let start = Date()
        mounts.releaseAll(waiting: 0.2)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(Set(fake.unmounted) == ["/Volumes/a", "/Volumes/b"])
        #expect(mounts.ownedMountpoints == ["/Volumes/a", "/Volumes/b"])
    }

    @Test func releaseAllUnmountsEveryOwnedMount() {
        let fake = FakeUnmounter()
        let mounts = SMBMounts(unmount: fake.unmount)
        mounts.register("/Volumes/a")
        mounts.releaseAll(waiting: 2)
        #expect(mounts.ownedMountpoints.isEmpty)
    }

    @Test func classifiesAuthenticationFailures() {
        #expect(SMBMountError(code: EAUTH) == .authentication)
        #expect(SMBMountError(code: ENEEDAUTH) == .authentication)
        #expect(SMBMountError(code: EACCES) == .authentication)
        #expect(SMBMountError(code: ENOENT) == .failed(ENOENT))
        #expect(SMBMountError(code: EHOSTUNREACH) == .failed(EHOSTUNREACH))
    }
}
