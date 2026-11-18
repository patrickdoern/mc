import AppKit
import MCCore

final class OperationRunner {
    final class Job {
        let title: String
        let operation: FileOperation
        fileprivate let sheet: ProgressSheet
        fileprivate(set) var percent: Int?
        fileprivate(set) var isBackground = false

        fileprivate init(title: String, operation: FileOperation, sheet: ProgressSheet) {
            self.title = title
            self.operation = operation
            self.sheet = sheet
        }
    }

    private let window: NSWindow
    private(set) var jobs: [Job] = []
    var onStatusChange: ((String) -> Void)?

    init(window: NSWindow) {
        self.window = window
    }

    var backgroundJobs: [Job] { jobs.filter(\.isBackground) }

    func run(title: String, _ work: @escaping (FileOperation) throws -> Void, completion: @escaping () -> Void) {
        let sheet = ProgressSheet(title: title)
        var job: Job?
        let operation = FileOperation(handlers: OperationHandlers(
            progress: { progress in
                DispatchQueue.main.async {
                    sheet.update(progress)
                    job?.percent = progress.bytesTotal > 0 ? Int(progress.bytesDone * 100 / progress.bytesTotal) : progress.filesTotal > 0 ? progress.filesDone * 100 / progress.filesTotal : nil
                    self.publishStatus()
                }
            },
            resolveConflict: { info in Settings.confirmOverwrite ? DispatchQueue.main.sync { Dialogs.conflict(info) } : .overwrite },
            resolveFailure: { path, error in DispatchQueue.main.sync { Dialogs.failure(path: path, error: error) } }
        ))
        let created = Job(title: title, operation: operation, sheet: sheet)
        job = created
        jobs.append(created)
        sheet.onCancel = { operation.cancel() }
        sheet.onBackground = { [weak self] in
            created.isBackground = true
            sheet.dismiss(from: self?.window)
            self?.publishStatus()
        }
        let reveal = DispatchWorkItem { [window] in
            if !created.isBackground { sheet.present(on: window) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: reveal)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work(operation) }
            DispatchQueue.main.async { [self] in
                reveal.cancel()
                sheet.dismiss(from: window)
                jobs.removeAll { $0 === created }
                publishStatus()
                if case .failure(let error) = result, !(error is OperationAborted) { Dialogs.show(error: error) }
                completion()
            }
        }
    }

    private func publishStatus() {
        let background = backgroundJobs
        switch background.count {
        case 0: onStatusChange?("")
        case 1: onStatusChange?("⟳ \(background[0].title)" + (background[0].percent.map { " \($0) %" } ?? ""))
        default: onStatusChange?("⟳ \(background.count) Hintergrundaufgaben")
        }
    }
}

private final class ProgressSheet {
    var onCancel: (() -> Void)?
    var onBackground: (() -> Void)?
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
        let background = NSButton(title: "Im Hintergrund", target: self, action: #selector(moveToBackground))
        let buttons = NSStackView(views: [background, cancel])
        let stack = NSStackView(views: [titleLabel, pathLabel, bar, detailLabel, buttons])
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

    func dismiss(from window: NSWindow?) {
        guard presented, let window else { return }
        presented = false
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

    @objc private func moveToBackground() {
        onBackground?()
    }
}
