import AppKit

final class ClassicDialog: NSView, NSTextFieldDelegate {
    private struct Item {
        enum Kind { case text, check, choice, button, progress }
        let kind: Kind
        var title = ""
        var field: NSTextField?
        var options: [String] = []
        var onChange: ((String) -> Void)?
        var isDefault = false
        var isCancel = false
        var checked = false
        var index = 0
        var detail = ""
        var fraction: Double?
    }

    private let dialogTitle: String
    private var message: String
    private let colors: Theme.DialogColors
    private var items: [Item] = []
    private var focus = 0
    private var result: Int?
    private var columns = 46
    private var onButton: ((Int?) -> Void)?
    private var dismissOverlay: (() -> Void)?
    private var frames: [Int: NSRect] = [:]
    private var textLines: [(String, CGFloat)] = []
    private var labels: [(String, CGFloat)] = []
    private let characterWidth = Theme.font.maximumAdvancement.width
    private let rowHeight: CGFloat = 22
    private let padding: CGFloat = 24

    init(title: String, message: String = "", warning: Bool = false) {
        dialogTitle = title
        self.message = message
        colors = Theme.dialogColors(warning: warning)
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    @discardableResult
    func addText(label: String = "", value: String = "", secure: Bool = false) -> NSTextField {
        let field: NSTextField = secure ? NSSecureTextField(string: value) : NSTextField(string: value)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = colors.fieldBackground
        field.textColor = colors.fieldText
        field.font = Theme.font
        field.focusRingType = .none
        field.delegate = self
        items.append(Item(kind: .text, title: label, field: field))
        return field
    }

    @discardableResult
    func addCheck(_ title: String, value: Bool) -> Int {
        items.append(Item(kind: .check, title: title, checked: value))
        return items.count - 1
    }

    @discardableResult
    func addChoice(label: String, options: [String], selected: Int, onChange: ((String) -> Void)? = nil) -> Int {
        items.append(Item(kind: .choice, title: label, options: options, onChange: onChange, index: selected))
        return items.count - 1
    }

    func addButton(_ title: String, isDefault: Bool = false, isCancel: Bool = false) {
        items.append(Item(kind: .button, title: title, isDefault: isDefault, isCancel: isCancel))
    }

    func addProgress() {
        items.append(Item(kind: .progress))
    }

    func updateProgress(path: String, fraction: Double?, detail: String) {
        guard let index = items.firstIndex(where: { $0.kind == .progress }) else { return }
        items[index].title = path
        items[index].fraction = fraction
        items[index].detail = detail
        needsDisplay = true
    }

    func setMessage(_ text: String) {
        message = text
        relayout()
    }

    func setOptions(_ itemIndex: Int, _ options: [String]) {
        let item = items[itemIndex]
        let selected = item.options.indices.contains(item.index) ? item.options[item.index] : nil
        items[itemIndex].options = options
        items[itemIndex].index = selected.flatMap(options.firstIndex(of:)) ?? 0
        relayout()
    }

    func interrupt() {
        guard let panel = window as? ClassicPanel, NSApp.modalWindow === panel else { return }
        result = nil
        NSApp.abortModal()
    }

    private func relayout() {
        layoutDialog()
        needsDisplay = true
        guard let panel = window as? ClassicPanel else { return }
        let old = panel.frame
        panel.setFrame(NSRect(x: old.midX - frame.width / 2, y: old.maxY - frame.height, width: frame.width, height: frame.height), display: true)
    }

    func presentSheet(on window: NSWindow, onButton: @escaping (Int?) -> Void) {
        layoutDialog()
        self.onButton = onButton
        focus = items.firstIndex { $0.kind == .button && $0.isDefault } ?? 0
        dismissOverlay = ClassicOverlay.present(self, in: window)
        applyFocus()
    }

    func dismissSheet(from window: NSWindow) {
        guard let dismiss = dismissOverlay else { return }
        dismissOverlay = nil
        onButton = nil
        dismiss()
    }

    func isChecked(_ itemIndex: Int) -> Bool { items[itemIndex].checked }
    func choice(_ itemIndex: Int) -> Int { items[itemIndex].index }

    func run() -> Int? {
        layoutDialog()
        let panel = ClassicPanel(contentRect: NSRect(origin: .zero, size: frame.size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = self
        panel.level = .modalPanel
        panel.hasShadow = true
        panel.backgroundColor = colors.background
        let reference = NSApp.keyWindow?.frame ?? NSApp.mainWindow?.frame ?? NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: reference.midX - frame.width / 2, y: reference.midY - frame.height / 2 + 40))
        focus = items.firstIndex { [.text, .choice, .check].contains($0.kind) } ?? items.firstIndex { $0.kind == .button && $0.isDefault } ?? 0
        panel.makeKeyAndOrderFront(nil)
        applyFocus()
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return result
    }

    private func wrap(_ text: String, columns: Int) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                if current.isEmpty {
                    current = word
                } else if current.count + 1 + word.count <= columns {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = word
                }
            }
            lines.append(current)
        }
        return lines
    }

    private func buttonText(_ item: Item) -> String { item.isDefault ? "[< \(item.title) >]" : "[ \(item.title) ]" }

    private func controlText(_ item: Item) -> String {
        switch item.kind {
        case .check: return "[\(item.checked ? "x" : " ")] \(item.title)"
        case .choice: return "\(item.title.hasSuffix(":") ? item.title : item.title + ":") < \(item.options.isEmpty ? "" : item.options[item.index]) >"
        case .button: return buttonText(item)
        case .text, .progress: return item.title
        }
    }

    private func layoutDialog() {
        let longestMessage = message.components(separatedBy: "\n").map(\.count).max() ?? 0
        let longestControl = items.filter { $0.kind != .button && $0.kind != .progress }.map { controlText($0).count }.max() ?? 0
        let columns = min(max(46, dialogTitle.count + 8, min(longestMessage, 76), longestControl + 2), 76)
        self.columns = columns
        let width = CGFloat(columns) * characterWidth + 2 * padding
        var y: CGFloat = 26
        textLines = []
        labels = []
        frames = [:]
        let lines = message.isEmpty ? [] : wrap(message, columns: columns)
        for line in lines {
            textLines.append((line, y))
            y += 19
        }
        if !lines.isEmpty { y += 10 }
        var index = 0
        while index < items.count {
            let item = items[index]
            switch item.kind {
            case .text:
                if !item.title.isEmpty {
                    labels.append((item.title, y))
                    y += 19
                }
                let rect = NSRect(x: padding, y: y, width: width - 2 * padding, height: 20)
                frames[index] = rect
                item.field?.frame = rect
                if let field = item.field, field.superview == nil { addSubview(field) }
                y += rowHeight + 6
                index += 1
            case .progress:
                frames[index] = NSRect(x: padding, y: y, width: width - 2 * padding, height: 62)
                y += 70
                index += 1
            case .check, .choice:
                frames[index] = NSRect(x: padding, y: y, width: CGFloat(controlText(item).count) * characterWidth, height: 20)
                y += rowHeight
                index += 1
            case .button:
                var group: [Int] = []
                var used = 0
                while index < items.count, items[index].kind == .button {
                    let size = buttonText(items[index]).count + 2
                    if !group.isEmpty && used + size > columns + 2 { break }
                    group.append(index)
                    used += size
                    index += 1
                }
                var x = (width - CGFloat(used - 2) * characterWidth) / 2
                for button in group {
                    let size = CGFloat(buttonText(items[button]).count) * characterWidth
                    frames[button] = NSRect(x: x, y: y, width: size, height: 20)
                    x += size + 2 * characterWidth
                }
                y += rowHeight + 6
            }
        }
        setFrameSize(NSSize(width: width, height: y + 20))
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
        let title = " \(dialogTitle) "
        let titleWidth = CGFloat(title.count) * characterWidth
        let titleRect = NSRect(x: (bounds.width - titleWidth) / 2, y: 0, width: titleWidth, height: 20)
        colors.background.setFill()
        titleRect.fill()
        draw(title, at: NSPoint(x: titleRect.minX, y: 2), color: colors.text, bold: true)
        for (line, y) in textLines { draw(line, at: NSPoint(x: padding, y: y), color: colors.text) }
        for (label, y) in labels { draw(label, at: NSPoint(x: padding, y: y), color: colors.text) }
        for (index, item) in items.enumerated() where item.kind == .progress {
            guard let rect = frames[index] else { continue }
            drawProgress(item, in: rect)
        }
        for (index, item) in items.enumerated() where item.kind != .text && item.kind != .progress {
            guard let rect = frames[index] else { continue }
            let focused = index == focus
            if focused {
                colors.focusBackground.setFill()
                rect.fill()
            }
            draw(controlText(item), at: NSPoint(x: rect.minX, y: rect.minY + 2), color: focused ? colors.focusText : colors.text, bold: item.kind == .button && item.isDefault)
        }
    }

    private func drawProgress(_ item: Item, in rect: NSRect) {
        var path = item.title
        if path.count > columns { path = "…" + path.suffix(columns - 1) }
        draw(path, at: NSPoint(x: rect.minX, y: rect.minY), color: colors.text)
        let bar = NSRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: 16)
        colors.fieldBackground.setFill()
        bar.fill()
        if let fraction = item.fraction {
            colors.focusBackground.setFill()
            NSRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(min(max(fraction, 0), 1)), height: bar.height).fill()
            let label = Formatting.percent(Int(fraction * 100))
            let width = CGFloat(label.count) * characterWidth
            draw(label, at: NSPoint(x: bar.midX - width / 2, y: bar.minY), color: colors.fieldText)
        }
        colors.border.setStroke()
        NSBezierPath(rect: bar.insetBy(dx: 0.5, dy: 0.5)).stroke()
        draw(item.detail, at: NSPoint(x: rect.minX, y: rect.minY + 46), color: colors.text)
    }

    private func draw(_ text: String, at point: NSPoint, color: NSColor, bold: Bool = false) {
        (text as NSString).draw(at: point, withAttributes: [.font: bold ? Theme.boldFont : Theme.font, .foregroundColor: color])
    }

    private func applyFocus() {
        if items[focus].kind == .text, let field = items[focus].field {
            window?.makeFirstResponder(field)
            (field.currentEditor() as? NSTextView)?.insertionPointColor = colors.fieldText
        } else {
            window?.makeFirstResponder(self)
        }
        needsDisplay = true
    }

    private func moveFocus(by delta: Int) {
        repeat { focus = (focus + delta + items.count) % items.count } while items[focus].kind == .progress
        applyFocus()
    }

    private func finish(button itemIndex: Int?) {
        if let itemIndex {
            result = items[0...itemIndex].filter { $0.kind == .button }.count - 1
        } else if let cancel = items.firstIndex(where: { $0.kind == .button && $0.isCancel }) {
            result = items[0...cancel].filter { $0.kind == .button }.count - 1
        }
        if let onButton {
            onButton(result)
        } else {
            NSApp.stopModal()
        }
    }

    private func activate() {
        switch items[focus].kind {
        case .button:
            finish(button: focus)
        case .check:
            items[focus].checked.toggle()
            needsDisplay = true
        case .progress:
            break
        case .choice, .text:
            if let defaultButton = items.firstIndex(where: { $0.kind == .button && $0.isDefault }) { finish(button: defaultButton) }
        }
    }

    private func cycleChoice(_ delta: Int) {
        guard items[focus].kind == .choice else { return }
        let count = items[focus].options.count
        guard count > 0 else { return }
        items[focus].index = (items[focus].index + delta + count) % count
        items[focus].onChange?(items[focus].options[items[focus].index])
        needsDisplay = true
    }

    private func moveAmongButtons(_ delta: Int) {
        let buttons = items.indices.filter { items[$0].kind == .button }
        guard let position = buttons.firstIndex(of: focus) else { return }
        focus = buttons[(position + delta + buttons.count) % buttons.count]
        applyFocus()
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .carriageReturn, .enter: activate()
        case .tab: moveFocus(by: 1)
        case .backTab: moveFocus(by: -1)
        case .upArrow: moveFocus(by: -1)
        case .downArrow: moveFocus(by: 1)
        case .leftArrow: items[focus].kind == .button ? moveAmongButtons(-1) : cycleChoice(-1)
        case .rightArrow: items[focus].kind == .button ? moveAmongButtons(1) : cycleChoice(1)
        default:
            if event.keyCode == 53 {
                finish(button: nil)
            } else if event.characters == " " {
                activate()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = frames.first(where: { items[$0.key].kind != .text && items[$0.key].kind != .progress && $0.value.contains(point) })?.key else { return }
        focus = index
        applyFocus()
        if items[index].kind == .choice { cycleChoice(1) } else { activate() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(insertNewline(_:)): activate()
        case #selector(insertTab(_:)), #selector(moveDown(_:)): moveFocus(by: 1)
        case #selector(insertBacktab(_:)), #selector(moveUp(_:)): moveFocus(by: -1)
        case #selector(cancelOperation(_:)): finish(button: nil)
        default: return false
        }
        return true
    }
}

final class ClassicPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
