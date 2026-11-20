import Foundation

public struct SSHTarget: Equatable {
    public var alias: String
    public var user: String?
    public var port: Int?
    public var path: String?

    public init(alias: String, user: String? = nil, port: Int? = nil, path: String? = nil) {
        self.alias = alias
        self.user = user
        self.port = port
        self.path = path
    }

    public static func parse(_ text: String) -> SSHTarget? {
        var rest = text.trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("sftp://") { rest = String(rest.dropFirst("sftp://".count)) }
        guard !rest.isEmpty else { return nil }
        var path: String?
        if let slash = rest.firstIndex(of: "/") {
            path = String(rest[slash...])
            rest = String(rest[..<slash])
        }
        var user: String?
        if let at = rest.lastIndex(of: "@") {
            user = String(rest[..<at])
            rest = String(rest[rest.index(after: at)...])
        }
        var port: Int?
        if let colon = rest.lastIndex(of: ":"), let value = Int(rest[rest.index(after: colon)...]) {
            port = value
            rest = String(rest[..<colon])
        }
        guard !rest.isEmpty, user?.isEmpty != true else { return nil }
        return SSHTarget(alias: rest, user: user, port: port, path: path)
    }

    public var displayName: String {
        var name = alias
        if let user { name = user + "@" + name }
        if let port { name += ":\(port)" }
        return name
    }
}

public struct SSHSettings {
    public let hostName: String
    public let user: String
    public let port: Int
    public let identityFiles: [String]
    public let identityAgent: String?
    public let knownHostsFile: String
    /// Wert von ProxyJump aus der SSH-Konfiguration; die Verbindung läuft dann über `ssh -W`.
    public var proxyJump: String?

    /// Argumente für `/usr/bin/ssh`, die dieselbe Verbindung wie das SFTP-Panel aufbauen.
    public var sshArguments: [String] {
        var arguments = ["-p", String(port), "-l", user, "-o", "UserKnownHostsFile=" + knownHostsFile]
        if let proxyJump { arguments += ["-J", proxyJump] }
        for file in identityFiles { arguments += ["-i", file] }
        if let identityAgent { arguments += ["-o", "IdentityAgent=" + identityAgent] }
        arguments.append(hostName)
        return arguments
    }

    public static func resolve(_ target: SSHTarget) throws -> SSHSettings {
        var arguments = ["-G"]
        if let config = ProcessInfo.processInfo.environment["MC_SSH_CONFIG"] { arguments += ["-F", config] }
        if let user = target.user { arguments += ["-l", user] }
        if let port = target.port { arguments += ["-p", String(port)] }
        arguments.append(target.alias)
        let output = try run("/usr/bin/ssh", arguments)
        var values: [String: [String]] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            if parts.count == 2 { values[parts[0], default: []].append(parts[1]) }
        }
        let jump = values["proxyjump"]?.first.flatMap { $0 == "none" ? nil : $0 }
        if let command = values["proxycommand"]?.first, command != "none" { throw FileError("ProxyCommand wird nicht unterstützt") }
        guard let hostName = values["hostname"]?.first, let user = values["user"]?.first else { throw FileError("SSH-Konfiguration für \(target.alias) nicht lesbar") }
        let agent = values["identityagent"]?.first.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        return SSHSettings(
            hostName: hostName,
            user: user,
            port: values["port"]?.first.flatMap { Int($0) } ?? 22,
            identityFiles: (values["identityfile"] ?? []).map(expandHome),
            identityAgent: agent.flatMap { $0 == "none" || $0 == "SSH_AUTH_SOCK" ? nil : expandHome($0) },
            knownHostsFile: expandHome((values["userknownhostsfile"]?.first ?? "~/.ssh/known_hosts").split(separator: " ").first.map(String.init) ?? "~/.ssh/known_hosts"),
            proxyJump: jump
        )
    }

    private static func expandHome(_ path: String) -> String {
        path.hasPrefix("~/") ? NSHomeDirectory() + String(path.dropFirst(1)) : path
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FileError("ssh -G fehlgeschlagen") }
        return String(decoding: data, as: UTF8.self)
    }
}
