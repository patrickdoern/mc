import AppKit
import MCCore

final class FindWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((String) -> Void)?
    var onClose: ((FindWindowController) -> Void)?

    private let table = ResultsTable()
    private let status = NSTextField(labelWithString: "Suche läuft …")
    private let lock = NSLock()
    private var pending: [String] = []
    private var finished = false
    private var cancelled = false
    private var results: [String] = []
    private var timer: Timer?

    init(fileSystem: FileSystem, root: String, criteria: SearchCriteria) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 480), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Suche in \(root)"
        window.delegate = self
        window.tabbingMode = .disallowed
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.title = "Pfad"
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(selectResult)
        table.onReturn = { [weak self] in self?.selectResult() }
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        let stack = NSStackView(views: [scroll, status])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 6, right: 8)
        window.contentView = stack
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.drain() }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            FileSearch.run(on: fileSystem, root: root, criteria: criteria, isCancelled: { isCancelled }) { path in
                lock.lock()
                pending.append(path)
                lock.unlock()
            }
            lock.lock()
            finished = true
            lock.unlock()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending = []
        let done = finished
        lock.unlock()
        if !batch.isEmpty {
            results += batch
            table.reloadData()
        }
        status.stringValue = "\(results.count) gefunden" + (done ? "" : " – Suche läuft …") + "  ·  Doppelklick oder Enter springt zur Datei"
        if done && batch.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    @objc private func selectResult() {
        guard results.indices.contains(table.selectedRow) else { return }
        onSelect?(results[table.selectedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: results[row])
        label.font = Theme.font
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    func windowWillClose(_ notification: Notification) {
        lock.lock()
        cancelled = true
        lock.unlock()
        timer?.invalidate()
        onClose?(self)
    }
}

private final class ResultsTable: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .carriageReturn || event.specialKey == .enter { return onReturn?() ?? () }
        if event.keyCode == 53 { return window?.close() ?? () }
        super.keyDown(with: event)
    }
}
