import AppKit
import SwiftTerm

final class ShellTerminal: LocalProcessTerminalView, LocalProcessTerminalViewDelegate {
    var onExit: (() -> Void)?
    let identity: String

    convenience init(directory: String) {
        self.init(identity: "local", executable: "/bin/zsh", args: ["-l", "-c", "cd \(Shell.quote(directory)) && exec /bin/zsh -l"])
    }

    /// Interaktive ssh-Sitzung im Ordner des SFTP-Panels.
    convenience init(identity: String, sshArguments: [String], directory: String) {
        self.init(identity: identity, executable: "/usr/bin/ssh", args: ["-t"] + sshArguments + ["cd \(Shell.quote(directory)) 2>/dev/null; exec \"${SHELL:-/bin/sh}\" -l"])
    }

    private init(identity: String, executable: String, args: [String]) {
        self.identity = identity
        super.init(frame: .zero)
        processDelegate = self
        font = Theme.font
        nativeBackgroundColor = .black
        nativeForegroundColor = NSColor(white: 0.85, alpha: 1)
        let environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        startProcess(executable: executable, args: args, environment: environment, execName: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var knownShellPid: pid_t = 0

    private var shellPid: pid_t {
        if knownShellPid == 0 { knownShellPid = Self.childShell() }
        return knownShellPid
    }

    var isIdle: Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard shellPid > 0, proc_pidinfo(shellPid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return info.e_tpgid == info.pbi_pgid
    }

    var workingDirectory: String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(shellPid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    func follow(_ newDirectory: String) {
        guard isIdle, workingDirectory != Self.resolved(newDirectory) else { return }
        send(txt: "\u{15}cd \(Shell.quote(newDirectory))\n")
    }

    func run(_ command: String) {
        send(txt: command + "\n")
    }

    private static func childShell() -> pid_t {
        var pids = [pid_t](repeating: 0, count: 64)
        proc_listchildpids(getpid(), &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.first { pid in
            guard pid > 0 else { return false }
            var name = [CChar](repeating: 0, count: 64)
            return proc_name(pid, &name, UInt32(name.count)) > 0 && String(cString: name) == "zsh"
        } ?? 0
    }

    private static func resolved(_ path: String) -> String {
        realpath(path, nil).map { resolved in
            defer { free(resolved) }
            return String(cString: resolved)
        } ?? path
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [self] in onExit?() }
    }
}
