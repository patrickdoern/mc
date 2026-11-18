import AppKit
import SwiftTerm

final class ShellTerminal: LocalProcessTerminalView, LocalProcessTerminalViewDelegate {
    var onExit: (() -> Void)?
    private(set) var directory: String

    init(directory: String) {
        self.directory = directory
        super.init(frame: .zero)
        processDelegate = self
        font = Theme.font
        nativeBackgroundColor = .black
        nativeForegroundColor = NSColor(white: 0.85, alpha: 1)
        let environment = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        startProcess(executable: "/bin/zsh", args: ["-l", "-c", "cd \(Shell.quote(directory)) && exec /bin/zsh -l"], environment: environment, execName: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func run(_ command: String, in newDirectory: String) {
        if newDirectory != directory {
            send(txt: "cd \(Shell.quote(newDirectory))\n")
            directory = newDirectory
        }
        send(txt: command + "\n")
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [self] in onExit?() }
    }
}
