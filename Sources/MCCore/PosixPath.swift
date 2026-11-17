public enum PosixPath {
    public static func join(_ base: String, _ name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }

    public static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), slash != path.startIndex else { return "/" }
        return String(path[..<slash])
    }

    public static func name(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }

    public static func resolve(_ path: String, relativeTo base: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return normalize(join(home, String(path.dropFirst(2)))) }
        if path.hasPrefix("/") { return normalize(path) }
        return normalize(join(base, path))
    }

    public static func relative(from directory: String, to path: String) -> String {
        let base = directory.split(separator: "/")
        let target = path.split(separator: "/")
        let common = zip(base, target).prefix { $0 == $1 }.count
        let parts = Array(repeating: "..", count: base.count - common) + target[common...].map(String.init)
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}
