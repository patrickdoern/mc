import Foundation
import NetFS

public struct SMBMount: Equatable {
    public let source: String
    public let mountpoint: String

    public init(source: String, mountpoint: String) {
        self.source = source
        self.mountpoint = mountpoint
    }
}

public struct SMBVolume: Equatable {
    public let mountpoint: String
    public let owned: Bool
}

public enum SMBMountError: Error, Equatable {
    case authentication
    case failed(Int32)

    static let authenticationCodes: Set<Int32> = [EAUTH, ENEEDAUTH, EACCES]

    init(code: Int32) {
        self = Self.authenticationCodes.contains(code) ? .authentication : .failed(code)
    }
}

public final class SMBMounts: @unchecked Sendable {
    public static let shared = SMBMounts { mountpoint, done in
        FileManager.default.unmountVolume(at: URL(fileURLWithPath: mountpoint), options: []) { done($0 == nil) }
    }

    private let unmount: (String, @escaping @Sendable (Bool) -> Void) -> Void
    private let lock = NSLock()
    private var owned: Set<String> = []
    private var pending: Set<String> = []
    private var held: Set<String> = []

    init(unmount: @escaping (String, @escaping @Sendable (Bool) -> Void) -> Void) {
        self.unmount = unmount
    }

    var ownedMountpoints: Set<String> { lock.withLock { owned } }

    var heldMountpoints: Set<String> { lock.withLock { held } }

    func register(_ mountpoint: String) {
        lock.withLock { _ = owned.insert(mountpoint) }
    }

    func hold(_ mountpoint: String) {
        lock.withLock { _ = held.insert(mountpoint) }
    }

    public func abandon(_ mountpoint: String) {
        lock.withLock { _ = held.remove(mountpoint) }
    }

    public func mount(_ target: SMBTarget, password: String?) throws -> SMBVolume {
        if let mountpoint = Self.existingMountpoint(for: target, in: Self.currentMounts()) {
            let isOwned = lock.withLock {
                guard owned.contains(mountpoint) else { return false }
                held.insert(mountpoint)
                return true
            }
            return SMBVolume(mountpoint: mountpoint, owned: isOwned)
        }
        guard let url = target.mountURL else { throw SMBAddressError.invalid(target.displayName) }
        let user = target.user.map { name in target.domain.map { $0 + ";" + name } ?? name }
        let openOptions = NSMutableDictionary(dictionary: [kNAUIOptionKey: kNAUIOptionNoUI])
        var mountpoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(url as CFURL, nil, user as CFString?, password as CFString?, openOptions, nil, &mountpoints)
        guard status == 0 else { throw SMBMountError(code: status) }
        guard let mountpoint = (mountpoints?.takeRetainedValue() as? [String])?.first else { throw SMBMountError.failed(EIO) }
        register(mountpoint)
        hold(mountpoint)
        return SMBVolume(mountpoint: mountpoint, owned: true)
    }

    public func release(keeping panelPaths: [String]) {
        let paths = panelPaths.flatMap { [$0] + (LocalFileSystem.shared.canonicalPath($0).map { [$0] } ?? []) }
        let candidates = lock.withLock {
            held = held.filter { !Self.isUsed($0, by: paths) }
            return Self.unused(owned: owned.subtracting(pending), held: held, panelPaths: paths)
        }
        for mountpoint in candidates { start(mountpoint, done: {}) }
    }

    public func releaseAll(waiting timeout: TimeInterval) {
        let group = DispatchGroup()
        for mountpoint in lock.withLock({ owned.subtracting(pending) }) {
            group.enter()
            start(mountpoint) { group.leave() }
        }
        _ = group.wait(timeout: .now() + timeout)
    }

    private func start(_ mountpoint: String, done: @escaping @Sendable () -> Void) {
        lock.withLock { _ = pending.insert(mountpoint) }
        unmount(mountpoint) { [self] success in
            lock.withLock {
                pending.remove(mountpoint)
                if success {
                    owned.remove(mountpoint)
                    held.remove(mountpoint)
                }
            }
            done()
        }
    }

    public static func unused(owned: Set<String>, held: Set<String>, panelPaths: [String]) -> [String] {
        owned.subtracting(held).filter { !isUsed($0, by: panelPaths) }.sorted()
    }

    static func isUsed(_ mountpoint: String, by panelPaths: [String]) -> Bool {
        panelPaths.contains { isPath($0, within: mountpoint) }
    }

    static func isPath(_ path: String, within directory: String) -> Bool {
        let base = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return path == base || path.hasPrefix(base + "/")
    }

    public static func existingMountpoint(for target: SMBTarget, in mounts: [SMBMount]) -> String? {
        mounts.first { mount in
            guard let (host, share) = hostAndShare(of: mount.source) else { return false }
            return host.caseInsensitiveCompare(target.host) == .orderedSame && share.caseInsensitiveCompare(target.share) == .orderedSame
        }?.mountpoint
    }

    public static func displayName(containing path: String) -> String? {
        displayName(containing: path, in: currentMounts())
    }

    static func displayName(containing path: String, in mounts: [SMBMount]) -> String? {
        guard let mount = mounts.first(where: { isPath(path, within: $0.mountpoint) }), let (host, share) = hostAndShare(of: mount.source) else { return nil }
        return SMBTarget(host: host, share: share).displayName
    }

    static func hostAndShare(of source: String) -> (host: String, share: String)? {
        guard source.hasPrefix("//") else { return nil }
        let rest = source.dropFirst(2)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        var host = String(rest[..<slash])
        if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
        let location = rest[rest.index(after: slash)...]
        let share = String(location[..<(location.firstIndex(of: "/") ?? location.endIndex)])
        if let colon = host.lastIndex(of: ":"), Int(host[host.index(after: colon)...]) != nil { host = String(host[..<colon]) }
        guard let decodedHost = host.removingPercentEncoding, let decodedShare = share.removingPercentEncoding, !decodedHost.isEmpty, !decodedShare.isEmpty else { return nil }
        return (decodedHost, decodedShare)
    }

    static func currentMounts() -> [SMBMount] {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        return UnsafeBufferPointer(start: buffer, count: Int(count)).compactMap { info in
            var info = info
            let type = withUnsafeBytes(of: &info.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard type == "smbfs" else { return nil }
            let source = withUnsafeBytes(of: &info.f_mntfromname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let mountpoint = withUnsafeBytes(of: &info.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return SMBMount(source: source, mountpoint: mountpoint)
        }
    }
}
