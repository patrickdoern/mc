import AppKit

final class MenuLineView: NSView {
    private let titles: [String]
    private let menuProvider: (Int) -> NSMenu
    private var highlighted: Int?
    private var dropdown: DropdownView?
    private var previousResponder: NSResponder?

    init(titles: [String], menu: @escaping (Int) -> NSMenu) {
        self.titles = titles
        menuProvider = menu
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func frame(ofItem index: Int) -> NSRect {
        let width = Theme.font.maximumAdvancement.width
        var x: CGFloat = 8
        for position in 0..<index { x += CGFloat(titles[position].count + 2) * width + 6 }
        return NSRect(x: x, y: 0, width: CGFloat(titles[index].count + 2) * width, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyBarLabelBackground.setFill()
        bounds.fill()
        for (index, title) in titles.enumerated() {
            let rect = frame(ofItem: index)
            if index == highlighted {
                Theme.keyBarBackground.setFill()
                rect.fill()
            }
            let color = index == highlighted ? Theme.keyBarNumber : Theme.keyBarLabel
            (" " + title + " " as NSString).draw(at: NSPoint(x: rect.minX, y: 3), withAttributes: [.font: Theme.font, .foregroundColor: color])
        }
    }

    func open(_ index: Int) {
        guard let window, let content = window.contentView else { return }
        if dropdown == nil { previousResponder = window.firstResponder }
        removeDropdown()
        highlighted = index
        needsDisplay = true
        let view = DropdownView(menu: menuProvider(index))
        let rect = convert(frame(ofItem: index), to: content)
        view.frame.origin = NSPoint(x: rect.minX, y: content.isFlipped ? rect.maxY : rect.minY - view.frame.height)
        view.onSwitch = { [weak self] delta in
            guard let self else { return }
            open((index + delta + titles.count) % titles.count)
        }
        view.onDismiss = { [weak self] item in
            self?.close()
            item?.perform()
        }
        dropdown = view
        content.addSubview(view)
        window.makeFirstResponder(view)
    }

    private func removeDropdown() {
        dropdown?.removeFromSuperview()
        dropdown = nil
    }

    private func close() {
        guard dropdown != nil else { return }
        removeDropdown()
        highlighted = nil
        needsDisplay = true
        window?.makeFirstResponder(previousResponder)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = titles.indices.first(where: { frame(ofItem: $0).contains(point) }) else { return }
        if highlighted == index { close() } else { open(index) }
    }
}

private final class DropdownView: NSView {
    var onSwitch: ((Int) -> Void)?
    var onDismiss: ((ClosureMenuItem?) -> Void)?

    private struct Row {
        let item: NSMenuItem
        let left: String
        let right: String
        let y: CGFloat
        let height: CGFloat
    }

    private let rows: [Row]
    private var current: Int?
    private let charWidth = Theme.font.maximumAdvancement.width

    init(menu: NSMenu) {
        var y: CGFloat = 4
        var built: [Row] = []
        var widest = 0
        for item in menu.items {
            let parts = item.title.components(separatedBy: "   ")
            let height: CGFloat = item.isSeparatorItem ? 9 : 19
            built.append(Row(item: item, left: (item.state == .on ? "✓ " : "  ") + parts[0], right: parts.count > 1 ? parts[1] : "", y: y, height: height))
            widest = max(widest, parts[0].count + 2 + (parts.count > 1 ? parts[1].count + 3 : 0))
            y += height
        }
        rows = built
        super.init(frame: NSRect(x: 0, y: 0, width: CGFloat(widest + 4) * Theme.font.maximumAdvancement.width, height: y + 4))
        current = rows.firstIndex { !$0.item.isSeparatorItem }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        DispatchQueue.main.async { [weak self] in
            if self?.superview != nil, self?.window?.firstResponder !== self { self?.onDismiss?(nil) }
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyBarLabelBackground.setFill()
        bounds.fill()
        Theme.keyBarBackground.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        for (index, row) in rows.enumerated() {
            if row.item.isSeparatorItem {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 4, y: row.y + row.height / 2))
                line.line(to: NSPoint(x: bounds.width - 4, y: row.y + row.height / 2))
                line.stroke()
                continue
            }
            let selected = index == current
            if selected {
                Theme.keyBarBackground.setFill()
                NSRect(x: 3, y: row.y, width: bounds.width - 6, height: row.height).fill()
            }
            let color = selected ? Theme.keyBarNumber : Theme.keyBarLabel
            (row.left as NSString).draw(at: NSPoint(x: 6, y: row.y + 2), withAttributes: [.font: Theme.font, .foregroundColor: color])
            if !row.right.isEmpty {
                let x = bounds.width - 6 - CGFloat(row.right.count) * charWidth
                (row.right as NSString).draw(at: NSPoint(x: x, y: row.y + 2), withAttributes: [.font: Theme.font, .foregroundColor: color])
            }
        }
    }

    private func move(_ delta: Int) {
        let selectable = rows.indices.filter { !rows[$0].item.isSeparatorItem }
        guard let position = selectable.firstIndex(where: { $0 == current }) else { return }
        current = selectable[(position + delta + selectable.count) % selectable.count]
        needsDisplay = true
    }

    private func row(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        return rows.indices.first { !rows[$0].item.isSeparatorItem && point.y >= rows[$0].y && point.y < rows[$0].y + rows[$0].height }
    }

    override func mouseMoved(with event: NSEvent) {
        if let index = row(at: event), index != current {
            current = index
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let index = row(at: event) else { return }
        onDismiss?(rows[index].item as? ClosureMenuItem)
    }

    override func keyDown(with event: NSEvent) {
        switch event.specialKey {
        case .upArrow: move(-1)
        case .downArrow: move(1)
        case .leftArrow: onSwitch?(-1)
        case .rightArrow: onSwitch?(1)
        case .carriageReturn, .enter: onDismiss?(current.flatMap { rows[$0].item as? ClosureMenuItem })
        default:
            if event.keyCode == 53 { onDismiss?(nil) }
        }
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError() }

    func perform() {
        handler()
    }

    @objc private func fire() {
        perform()
    }
}
