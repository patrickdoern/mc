import AppKit
import MCCore

final class FindDialog: NSView {
    var onSelect: ((String) -> Void)?
    var onPanelize: (([String]) -> Void)?
    var onClose: (() -> Void)?

    private static let buttonTitles = [localized("Gehe zu"), localized("Als Panel"), localized("Abbrechen")]
    private let colors = Theme.dialogColors(warning: false)
    private let titleText: String
    private let characterWidth = Theme.font.maximumAdvancement.width
    private let rowHeight: CGFloat = 19
    private let visibleRows = 14
    private let padding: CGFloat = 24
    private let columns = 76
    private let lock = NSLock()
    private var pending: [String] = []
    private var finished = false
    private var cancelled = false
    private var results: [String] = []
    private var cursor = 0
    private var top = 0
    private var focus = 0
    private var timer: Timer?
    private var dismissOverlay: (() -> Void)?
    private var buttonFrames: [NSRect] = []
    private var listFrame = NSRect.zero

    init(fileSystem: FileSystem, root: String, criteria: SearchCriteria) {
        titleText = localized("Suche in %@", root as NSString)
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(columns) * characterWidth + 2 * padding, height: 40 + CGFloat(14) * 19 + 90))
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.drain() }
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

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func present(on window: NSWindow) {
        dismissOverlay = ClassicOverlay.present(self, in: window)
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending = []
        let done = finished
        lock.unlock()
        if !batch.isEmpty { results += batch }
        if done && batch.isEmpty {
            timer?.invalidate()
            timer = nil
        }
        needsDisplay = true
    }

    private func closeDialog() {
        lock.lock()
        cancelled = true
        lock.unlock()
        timer?.invalidate()
        timer = nil
        dismissOverlay?()
        dismissOverlay = nil
        onClose?()
    }

    private func goToResult() {
        guard results.indices.contains(cursor) else { return }
        let path = results[cursor]
        closeDialog()
        onSelect?(path)
    }

    private func showAsPanel() {
        guard !results.isEmpty else { return }
        let paths = results
        closeDialog()
        onPanelize?(paths)
    }

    private func activateButton(_ index: Int) {
        switch index {
        case 0: goToResult()
        case 1: showAsPanel()
        default: closeDialog()
        }
    }

    private func moveCursor(by delta: Int) {
        guard !results.isEmpty else { return }
        cursor = min(max(cursor + delta, 0), results.count - 1)
        if cursor < top { top = cursor }
        if cursor >= top + visibleRows { top = cursor - visibleRows + 1 }
        needsDisplay = true
    }

    private func abbreviated(_ text: String, columns: Int) -> String {
        text.count > columns ? "…" + text.suffix(columns - 1) : text
    }

    private func statusText() -> String {
        lock.lock()
        let done = finished
        lock.unlock()
        return localized("%ld gefunden", results.count) + (done ? "" : " – " + localized("Suche läuft …"))
    }

    override func draw(_ dirtyRect: NSRect) {
        colors.background.setFill()
        bounds.fill()
        colors.border.setStroke()
        for inset in [CGFloat(5), 8] {
            let path = NSBezierPath(rect: bounds.insetBy(dx: inset + 0.5, dy: inset + 0.5))
            path.lineWidth = 1
            path.stroke()
        }
        let title = " \(titleText) "
        let shownTitle = abbreviated(title, columns: columns - 4)
        let titleWidth = CGFloat(shownTitle.count) * characterWidth
        let titleRect = NSRect(x: (bounds.width - titleWidth) / 2, y: 0, width: titleWidth, height: 20)
        colors.background.setFill()
        titleRect.fill()
        draw(shownTitle, at: NSPoint(x: titleRect.minX, y: 2), color: colors.text, bold: true)

        listFrame = NSRect(x: padding, y: 28, width: bounds.width - 2 * padding, height: CGFloat(visibleRows) * rowHeight)
        colors.fieldBackground.setFill()
        listFrame.fill()
        colors.border.setStroke()
        NSBezierPath(rect: listFrame.insetBy(dx: 0.5, dy: 0.5)).stroke()
        for offset in 0..<visibleRows {
            let index = top + offset
            guard index < results.count else { break }
            let rowRect = NSRect(x: listFrame.minX + 1, y: listFrame.minY + CGFloat(offset) * rowHeight, width: listFrame.width - 2, height: rowHeight)
            let selected = index == cursor
            if selected {
                (focus == 0 ? colors.focusBackground : colors.border.withAlphaComponent(0.4)).setFill()
                rowRect.fill()
            }
            draw(abbreviated(results[index], columns: columns - 2), at: NSPoint(x: rowRect.minX + 4, y: rowRect.minY + 2), color: selected && focus == 0 ? colors.focusText : colors.fieldText)
        }

        draw(statusText(), at: NSPoint(x: padding, y: listFrame.maxY + 8), color: colors.text)

        let texts = Self.buttonTitles.enumerated().map { $0.offset == 0 ? "[< \($0.element) >]" : "[ \($0.element) ]" }
        let total = texts.reduce(0) { $0 + $1.count } + 2 * (texts.count - 1)
        var x = (bounds.width - CGFloat(total) * characterWidth) / 2
        let y = listFrame.maxY + 34
        buttonFrames = []
        for (index, text) in texts.enumerated() {
            let rect = NSRect(x: x, y: y, width: CGFloat(text.count) * characterWidth, height: 20)
            buttonFrames.append(rect)
            if focus == index + 1 {
                colors.focusBackground.setFill()
                rect.fill()
            }
            draw(text, at: NSPoint(x: rect.minX, y: rect.minY + 2), color: focus == index + 1 ? colors.focusText : colors.text, bold: index == 0)
            x += rect.width + 2 * characterWidth
        }
    }

    private func draw(_ text: String, at point: NSPoint, color: NSColor, bold: Bool = false) {
        (text as NSString).draw(at: point, withAttributes: [.font: bold ? Theme.boldFont : Theme.font, .foregroundColor: color])
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .tab: focus = (focus + 1) % 4
        case .backTab: focus = (focus + 3) % 4
        case .upArrow: focus == 0 ? moveCursor(by: -1) : { focus = 0 }()
        case .downArrow: focus == 0 ? moveCursor(by: 1) : { focus = 0 }()
        case .pageUp: moveCursor(by: -visibleRows)
        case .pageDown: moveCursor(by: visibleRows)
        case .home: moveCursor(by: -results.count)
        case .end: moveCursor(by: results.count)
        case .leftArrow where focus > 0: focus = focus == 1 ? 3 : focus - 1
        case .rightArrow where focus > 0: focus = focus == 3 ? 1 : focus + 1
        case .carriageReturn, .enter: focus == 0 ? goToResult() : activateButton(focus - 1)
        default:
            if event.keyCode == 53 {
                closeDialog()
            } else if event.characters == " ", focus > 0 {
                activateButton(focus - 1)
            }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let button = buttonFrames.firstIndex(where: { $0.contains(point) }) {
            focus = button + 1
            activateButton(button)
            return
        }
        guard listFrame.contains(point) else { return }
        let index = top + Int((point.y - listFrame.minY) / rowHeight)
        guard index < results.count else { return }
        focus = 0
        cursor = index
        needsDisplay = true
        if event.clickCount == 2 { goToResult() }
    }

    override func scrollWheel(with event: NSEvent) {
        let lines = Int((-event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? rowHeight : 1)).rounded())
        guard lines != 0 else { return }
        top = max(min(top + lines, max(results.count - visibleRows, 0)), 0)
        needsDisplay = true
    }
}
