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

    func run(title: String, options: TransferOptions = TransferOptions(), _ work: @escaping (FileOperation) throws -> Void, completion: @escaping () -> Void) {
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
        ), options: options)
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
        case 1: onStatusChange?("⟳ \(background[0].title)" + (background[0].percent.map { " " + Formatting.percent($0) } ?? ""))
        default: onStatusChange?("⟳ " + localized("%ld Hintergrundaufgaben", background.count))
        }
    }
}

private final class ProgressSheet {
    var onCancel: (() -> Void)?
    var onBackground: (() -> Void)?
    private let dialog: ClassicDialog
    private var presented = false

    init(title: String) {
        dialog = ClassicDialog(title: title)
        dialog.addProgress()
        dialog.addButton(localized("Im Hintergrund"), isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
    }

    func present(on window: NSWindow) {
        presented = true
        dialog.presentSheet(on: window) { [weak self] button in
            if button == 0 { self?.onBackground?() } else { self?.onCancel?() }
        }
    }

    func dismiss(from window: NSWindow?) {
        guard presented, let window else { return }
        presented = false
        dialog.dismissSheet(from: window)
    }

    func update(_ progress: OperationProgress) {
        let total = progress.bytesTotal > 0 ? progress.bytesTotal : Int64(progress.filesTotal)
        let done = progress.bytesTotal > 0 ? progress.bytesDone : Int64(progress.filesDone)
        var detail = localized("%ld von %ld Dateien", progress.filesDone, progress.filesTotal)
        if progress.bytesTotal > 0 { detail += " · " + localized("%@ von %@", Formatting.exactSize(progress.bytesDone) as NSString, Formatting.exactSize(progress.bytesTotal) as NSString) }
        dialog.updateProgress(path: progress.currentPath, fraction: total > 0 ? Double(done) / Double(total) : nil, detail: detail)
    }
}
