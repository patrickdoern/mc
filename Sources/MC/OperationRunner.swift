import AppKit
import MCCore

final class OperationRunner {
    private let window: NSWindow
    private var sheet: ProgressSheet?
    private var operation: FileOperation?

    init(window: NSWindow) {
        self.window = window
    }

    func run(title: String, _ work: @escaping (FileOperation) throws -> Void, completion: @escaping () -> Void) {
        let sheet = ProgressSheet(title: title)
        self.sheet = sheet
        let operation = FileOperation(handlers: OperationHandlers(
            progress: { progress in DispatchQueue.main.async { sheet.update(progress) } },
            resolveConflict: { info in Settings.confirmOverwrite ? DispatchQueue.main.sync { Dialogs.conflict(info) } : .overwrite },
            resolveFailure: { path, error in DispatchQueue.main.sync { Dialogs.failure(path: path, error: error) } }
        ))
        self.operation = operation
        sheet.onCancel = { operation.cancel() }
        let reveal = DispatchWorkItem { [window] in sheet.present(on: window) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: reveal)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work(operation) }
            DispatchQueue.main.async { [self] in
                reveal.cancel()
                sheet.dismiss(from: window)
                self.sheet = nil
                self.operation = nil
                if case .failure(let error) = result, !(error is OperationAborted) { Dialogs.show(error: error) }
                completion()
            }
        }
    }
}

private final class ProgressSheet {
    var onCancel: (() -> Void)?
    private let panel: NSWindow
    private let pathLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var presented = false

    init(title: String) {
        panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 130), styleMask: [.titled], backing: .buffered, defer: false)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 13)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.textColor = .secondaryLabelColor
        bar.isIndeterminate = true
        bar.style = .bar
        bar.startAnimation(nil)
        let cancel = NSButton(title: "Abbrechen", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let stack = NSStackView(views: [titleLabel, pathLabel, bar, detailLabel, cancel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        panel.contentView = stack
        NSLayoutConstraint.activate([
            pathLabel.widthAnchor.constraint(equalToConstant: 420),
            bar.widthAnchor.constraint(equalToConstant: 420),
        ])
        cancel.setContentHuggingPriority(.required, for: .horizontal)
    }

    func present(on window: NSWindow) {
        presented = true
        window.beginSheet(panel)
    }

    func dismiss(from window: NSWindow) {
        guard presented else { return }
        window.endSheet(panel)
        panel.orderOut(nil)
    }

    func update(_ progress: OperationProgress) {
        pathLabel.stringValue = progress.currentPath
        let total = progress.bytesTotal > 0 ? progress.bytesTotal : Int64(progress.filesTotal)
        let done = progress.bytesTotal > 0 ? progress.bytesDone : Int64(progress.filesDone)
        bar.isIndeterminate = total == 0
        if total > 0 {
            bar.maxValue = Double(total)
            bar.doubleValue = Double(done)
        }
        var detail = "\(progress.filesDone) von \(progress.filesTotal) Dateien"
        if progress.bytesTotal > 0 { detail += " · \(Formatting.exactSize(progress.bytesDone)) von \(Formatting.exactSize(progress.bytesTotal))" }
        detailLabel.stringValue = detail
    }

    @objc private func cancel() {
        onCancel?()
    }
}
