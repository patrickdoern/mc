import AppKit

final class CommandOutputWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((CommandOutputWindowController) -> Void)?

    private let process = Process()
    private let textView = EditorTextView()
    private let finished = DispatchGroup()

    init(command: String, directory: String) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "$ " + command
        window.delegate = self
        window.tabbingMode = .disallowed
        textView.applyEditorStyle()
        textView.isEditable = false
        textView.onFunctionKey = { [weak self] number, _ in number == 10 ? { self?.close(); return true }() : false }
        textView.onEscape = { [weak self] in self?.close() }
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.backgroundColor = Theme.background
        window.contentView = scroll
        window.makeFirstResponder(textView)
        start(command, directory: directory)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func start(_ command: String, directory: String) {
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "dumb"]) { _, new in new }
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        finished.enter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                self?.finished.leave()
                return
            }
            DispatchQueue.main.async { self?.append(String(decoding: data, as: UTF8.self)) }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            finished.notify(queue: .main) { self.append("\n[Beendet mit Status \(process.terminationStatus)]\n") }
        }
        do {
            try process.run()
        } catch {
            append(error.localizedDescription)
        }
    }

    private func append(_ text: String) {
        textView.textStorage?.append(NSAttributedString(string: text, attributes: [.font: Theme.font, .foregroundColor: Theme.editorText]))
        textView.scrollToEndOfDocument(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if process.isRunning { process.terminate() }
        onClose?(self)
    }
}
