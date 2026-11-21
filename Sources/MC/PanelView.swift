import AppKit
import MCCore

enum PanelCommand {
    case activate
    case switchPanel
    case functionKey(Int, shifted: Bool)
    case openFile(FileEntry)
    case markPattern(select: Bool)
    case execute
    case insertName
    case complete
}

enum PanelMode: Int {
    case list, quickView, info, tree
}

final class PanelView: NSView {
    let model: PanelModel
    var onCommand: ((PanelCommand) -> Void)?
    var onModeChange: (() -> Void)?
    var peer: (() -> PanelModel)?
    var isActive = false { didSet { needsDisplay = true } }
    private(set) var mode = PanelMode.list

    private let commandLine: ShellInput
    private var tree: DirectoryTree?
    private var previewLines: [String] = []
    private var previewKey = ""
    private var topIndex = 0
    private let rowHeight: CGFloat = 17
    private let margin: CGFloat = 4
    private let charWidth = Theme.font.maximumAdvancement.width

    init(model: PanelModel, commandLine: ShellInput) {
        self.model = model
        self.commandLine = commandLine
        super.init(frame: .zero)
        model.onChange = { [weak self] in self?.needsDisplay = true }
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        onCommand?(.activate)
        return true
    }

    @objc private func themeDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    func setMode(_ newMode: PanelMode) {
        mode = newMode
        topIndex = 0
        tree = newMode == .tree ? DirectoryTree(fileSystem: model.fileSystem, path: model.path, showHidden: model.showHidden) { [weak self] in self?.needsDisplay = true } : nil
        refreshPreview()
        needsDisplay = true
        onModeChange?()
    }

    func refreshPreview() {
        guard mode == .quickView, let peerModel = peer?() else { return }
        guard let entry = peerModel.currentEntry, !peerModel.isParentRow(peerModel.cursor) else {
            previewKey = ""
            previewLines = []
            return
        }
        let path = peerModel.fullPath(of: entry.name)
        let system = peerModel.fileSystem
        let key = "\(system.identity)\(path)\(entry.size)\(entry.modified?.timeIntervalSince1970 ?? 0)"
        guard key != previewKey else { return }
        previewKey = key
        topIndex = 0
        guard !entry.isDirectory else {
            previewLines = [localized("<Ordner>")]
            return
        }
        previewLines = ["…"]
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let lines = Self.previewLines(of: path, on: system, size: entry.size)
            DispatchQueue.main.async {
                guard let self, key == self.previewKey else { return }
                self.previewLines = lines
                self.needsDisplay = true
            }
        }
    }

    private static func previewLines(of path: String, on system: FileSystem, size: Int64) -> [String] {
        guard let reader = try? system.openReader(path) else { return [localized("<Datei nicht lesbar>")] }
        defer { reader.close() }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        guard let count = try? buffer.withUnsafeMutableBytes({ try reader.read(into: $0) }) else { return [localized("<Datei nicht lesbar>")] }
        let data = Data(buffer[0..<count])
        guard !data.contains(0) else { return [localized("<Binärdatei, %@>", Formatting.exactSize(size) as NSString)] }
        return EditorWindowController.decode(data).0
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\t", with: "    ")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private var infoLines: [String] {
        peer.map { FileInfo.lines(for: $0()) } ?? []
    }

    private var listTop: CGFloat { margin + rowHeight }
    private var visibleRows: Int { max(Int((bounds.height - listTop - margin - rowHeight - 4) / rowHeight), 1) }
    private var columns: Int { Int((bounds.width - 2 * margin - 8) / charWidth) }
    private var briefColumns: Int { model.format == .brief ? (columns >= 90 ? 3 : 2) : 1 }
    private var cellColumns: Int { columns / briefColumns }
    private var pageSize: Int { visibleRows * briefColumns }

    private var itemCount: Int {
        switch mode {
        case .list: return model.rows.count
        case .tree: return tree?.rows.count ?? 0
        case .quickView: return previewLines.count
        case .info: return infoLines.count
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        drawFrame()
        keepCursorVisible()
        switch mode {
        case .list: drawList()
        case .tree: drawTree()
        case .quickView: drawLines(previewLines)
        case .info: drawLines(infoLines)
        }
        drawFooter()
    }

    private var title: String {
        switch mode {
        case .list: return model.title + (model.isLoading ? " …" : "")
        case .quickView: return localized("Schnellansicht")
        case .info: return localized("Info")
        case .tree: return localized("Baum")
        }
    }

    private func drawFrame() {
        let frame = bounds.insetBy(dx: margin, dy: margin).offsetBy(dx: 0, dy: rowHeight / 2)
        let path = NSBezierPath(rect: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: bounds.height - 2 * margin - rowHeight / 2))
        path.lineWidth = 1
        Theme.border.setStroke()
        path.stroke()
        let footer = NSBezierPath()
        let footerY = bounds.height - margin - rowHeight - 3
        footer.move(to: NSPoint(x: frame.minX, y: footerY))
        footer.line(to: NSPoint(x: frame.maxX, y: footerY))
        footer.stroke()
        let label = " " + abbreviated(title, columns: Int(frame.width / charWidth) - 4) + " "
        let labelSize = (label as NSString).size(withAttributes: [.font: Theme.font])
        let labelRect = NSRect(x: frame.minX + 12, y: margin, width: labelSize.width, height: rowHeight)
        (isActive ? Theme.cursor : Theme.background).setFill()
        labelRect.fill()
        draw(label, at: NSPoint(x: labelRect.minX, y: labelRect.minY), color: isActive ? Theme.cursorText : Theme.border)
    }

    private func drawList() {
        for offset in 0..<pageSize {
            let index = topIndex + offset
            guard index < model.rows.count else { break }
            drawRow(index, column: offset / visibleRows, y: listTop + CGFloat(offset % visibleRows) * rowHeight)
        }
    }

    private func trailingColumns(for entry: FileEntry, isParent: Bool) -> [(text: String, width: Int)] {
        let size = isParent ? "<UP>" : entry.isDirectory ? model.directorySizes[entry.name].map(Formatting.size) ?? "<DIR>" : Formatting.size(entry.size)
        switch model.format {
        case .full:
            return [(size, 8)] + (columns >= 42 && !isParent ? [(Formatting.date(entry.modified), 14)] : [])
        case .sizeOnly:
            return [(size, 8)]
        case .permissions:
            return [(isParent ? "" : Formatting.permissions(entry.permissions), 9), (size, 8)]
        case .namesOnly, .brief:
            return []
        }
    }

    private func drawRow(_ index: Int, column: Int, y: CGFloat) {
        let entry = model.rows[index]
        let isParent = model.isParentRow(index)
        let isMarked = model.marked.contains(entry.name)
        let isCursor = index == model.cursor
        let x = margin + 6 + CGFloat(column * cellColumns) * charWidth
        if isCursor {
            (isActive ? Theme.cursor : Theme.inactiveCursor).setFill()
            let width = briefColumns > 1 ? CGFloat(cellColumns) * charWidth - 2 : bounds.width - 2 * margin - 4
            NSRect(x: x - 4, y: y, width: width, height: rowHeight).fill()
        }
        let color = isCursor && isActive ? Theme.cursorText : isMarked ? Theme.marked : entry.isDirectory ? Theme.directory : Theme.text
        let trailing = trailingColumns(for: entry, isParent: isParent)
        let nameWidth = briefColumns > 1 ? cellColumns - 1 : columns - trailing.reduce(0) { $0 + $1.width + 1 }
        var label = entry.isDirectory ? "/" + entry.name : entry.name
        if entry.isSymlink && !entry.isDirectory { label = "@" + label }
        draw(abbreviated(label, columns: nameWidth), at: NSPoint(x: x, y: y), color: color, font: entry.isDirectory || isMarked ? Theme.boldFont : Theme.font)
        var offset = nameWidth
        for column in trailing {
            offset += 1
            let text = String(repeating: " ", count: max(column.width - column.text.count, 0)) + column.text
            draw(text, at: NSPoint(x: x + CGFloat(offset) * charWidth, y: y), color: color)
            offset += column.width
        }
    }

    private func drawTree() {
        guard let tree else { return }
        for offset in 0..<visibleRows {
            let index = topIndex + offset
            guard index < tree.rows.count else { break }
            let row = tree.rows[index]
            let y = listTop + CGFloat(offset) * rowHeight
            let isCursor = index == tree.cursor
            if isCursor {
                (isActive ? Theme.cursor : Theme.inactiveCursor).setFill()
                NSRect(x: margin + 2, y: y, width: bounds.width - 2 * margin - 4, height: rowHeight).fill()
            }
            let marker = row.isLeaf ? "  " : row.isExpanded ? "▾ " : "▸ "
            let text = String(repeating: "  ", count: row.depth) + marker + row.name
            draw(abbreviated(text, columns: columns), at: NSPoint(x: margin + 6, y: y), color: isCursor && isActive ? Theme.cursorText : Theme.directory)
        }
    }

    private func drawLines(_ lines: [String]) {
        for offset in 0..<visibleRows {
            let index = topIndex + offset
            guard index < lines.count else { break }
            draw(abbreviated(lines[index], columns: columns), at: NSPoint(x: margin + 6, y: listTop + CGFloat(offset) * rowHeight), color: Theme.text)
        }
    }

    private func drawFooter() {
        let y = bounds.height - margin - rowHeight
        var text = ""
        var color = Theme.text
        switch mode {
        case .tree:
            text = tree?.currentPath ?? ""
        case .quickView, .info:
            text = peer?().path ?? ""
        case .list:
            if let search = model.searchText {
                text = localized("Suche: ") + search
            } else if !model.marked.isEmpty {
                text = localized("%d markiert (%@)", model.marked.count, Formatting.exactSize(model.markedBytes) as NSString)
                color = Theme.marked
            } else if let entry = model.currentEntry, !model.isParentRow(model.cursor) {
                let size = entry.isDirectory ? "<DIR>" : Formatting.exactSize(entry.size)
                text = "\(entry.name)  \(size)  \(Formatting.permissions(entry.permissions))"
            } else {
                let count = max(model.rows.count - (model.hasParentRow ? 1 : 0), 0)
                text = count == 1 ? localized("%ld Eintrag", count) : localized("%ld Einträge", count)
            }
        }
        draw(abbreviated(text, columns: columns), at: NSPoint(x: margin + 6, y: y), color: color)
    }

    private func draw(_ text: String, at point: NSPoint, color: NSColor, font: NSFont = Theme.font) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func abbreviated(_ text: String, columns: Int) -> String {
        guard columns > 1, text.count > columns else { return text }
        return String(text.prefix(columns - 1)) + "…"
    }

    private func keepCursorVisible() {
        let cursor: Int?
        switch mode {
        case .list: cursor = model.cursor
        case .tree: cursor = tree?.cursor
        case .quickView, .info: cursor = nil
        }
        if mode == .list, briefColumns > 1 {
            topIndex = (model.cursor / pageSize) * pageSize
            return
        }
        if let cursor {
            if cursor < topIndex { topIndex = cursor }
            if cursor >= topIndex + visibleRows { topIndex = cursor - visibleRows + 1 }
        }
        topIndex = max(min(topIndex, max(itemCount - visibleRows, 0)), 0)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let column = mode == .list && briefColumns > 1 ? min(Int((point.x - margin) / (CGFloat(cellColumns) * charWidth)), briefColumns - 1) : 0
        let index = topIndex + column * visibleRows + Int((point.y - listTop) / rowHeight)
        guard point.y >= listTop, index < itemCount else { return }
        switch mode {
        case .list:
            model.setCursor(index)
            if event.clickCount == 2 { open() }
        case .tree:
            tree?.cursor = index
            needsDisplay = true
            if event.clickCount == 2 { selectTreeRow() }
        case .quickView, .info:
            break
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let lines = Int((-event.scrollingDeltaY / (event.hasPreciseScrollingDeltas ? rowHeight : 1)).rounded())
        guard lines != 0 else { return }
        if mode == .list, briefColumns > 1 {
            model.moveCursor(by: lines.signum() * visibleRows)
            return
        }
        topIndex = max(min(topIndex + lines, max(itemCount - visibleRows, 0)), 0)
        needsDisplay = true
    }

    override func selectAll(_ sender: Any?) {
        model.markAll()
    }

    @objc func findText(_ sender: Any?) {
        model.beginSearch()
    }

    private func open() {
        if let file = model.enterCursor() { onCommand?(.openFile(file)) }
    }

    private func selectTreeRow() {
        guard let path = tree?.currentPath else { return }
        model.navigate(to: path)
        setMode(.list)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mode == .list, model.searchText != nil, handleSearch(event) { return }
        if handleCommandLine(event, modifiers: modifiers) { return }
        let shifted = modifiers.contains(.shift)
        if mode != .list, handleViewKey(event) { return }
        if let key = event.specialKey, handleSpecial(key, modifiers: modifiers, shifted: shifted) { return }
        if modifiers.contains(.control), event.charactersIgnoringModifiers == "s" { return model.beginSearch() }
        switch event.characters {
        case " ": model.toggleMarkAndAdvance()
        case "+": onCommand?(.markPattern(select: true))
        case "-": onCommand?(.markPattern(select: false))
        case "*": model.invertMarks()
        default:
            if event.keyCode == 53 { model.clearMarks() } else { super.keyDown(with: event) }
        }
    }

    private func handleViewKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            setMode(.list)
            return true
        }
        guard let key = event.specialKey else { return false }
        if mode == .tree, let tree {
            switch key {
            case .upArrow: tree.move(by: -1)
            case .downArrow: tree.move(by: 1)
            case .pageUp: tree.move(by: -(visibleRows - 1))
            case .pageDown: tree.move(by: visibleRows - 1)
            case .home: tree.move(by: -tree.cursor)
            case .end: tree.move(by: tree.rows.count)
            case .rightArrow: tree.expand()
            case .leftArrow: tree.collapse()
            case .carriageReturn, .enter: selectTreeRow()
            case .delete: setMode(.list)
            default: return false
            }
            return true
        }
        switch key {
        case .upArrow: scrollText(by: -1)
        case .downArrow: scrollText(by: 1)
        case .pageUp: scrollText(by: -(visibleRows - 1))
        case .pageDown: scrollText(by: visibleRows - 1)
        case .home: scrollText(by: -topIndex)
        case .end: scrollText(by: itemCount)
        default: return false
        }
        return true
    }

    private func scrollText(by delta: Int) {
        topIndex = max(min(topIndex + delta, max(itemCount - visibleRows, 0)), 0)
        needsDisplay = true
    }

    private func handleCommandLine(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.control), let key = event.charactersIgnoringModifiers, key == "p" || key == "n" {
            if key == "p" { commandLine.recallPrevious() } else { commandLine.recallNext() }
            return true
        }
        if event.keyCode == 53, !commandLine.isEmpty {
            commandLine.clear()
            return true
        }
        if let key = event.specialKey {
            switch key {
            case .carriageReturn, .enter:
                guard modifiers.contains(.command) || !commandLine.isEmpty else { return false }
                onCommand?(modifiers.contains(.command) ? .insertName : .execute)
                return true
            case .delete:
                guard !commandLine.isEmpty else { return false }
                commandLine.deleteLast()
                return true
            case .tab:
                guard !commandLine.isEmpty else { return false }
                onCommand?(.complete)
                return true
            default:
                return false
            }
        }
        guard !modifiers.contains(.command), !modifiers.contains(.control), let characters = event.characters, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { return false }
        if commandLine.isEmpty && " +-*".contains(characters) { return false }
        commandLine.append(characters)
        return true
    }

    private func handleSpecial(_ key: NSEvent.SpecialKey, modifiers: NSEvent.ModifierFlags, shifted: Bool) -> Bool {
        switch key {
        case .upArrow:
            if modifiers.contains(.command) { model.goUp() } else { extendOrMove(-1, shifted: shifted) }
        case .downArrow:
            if modifiers.contains(.command) { open() } else { extendOrMove(1, shifted: shifted) }
        case .leftArrow where briefColumns > 1: model.moveCursor(by: -visibleRows)
        case .rightArrow where briefColumns > 1: model.moveCursor(by: visibleRows)
        case .pageUp: model.moveCursor(by: -(briefColumns > 1 ? pageSize : visibleRows - 1))
        case .pageDown: model.moveCursor(by: briefColumns > 1 ? pageSize : visibleRows - 1)
        case .home: model.setCursor(0)
        case .end: model.setCursor(model.rows.count - 1)
        case .carriageReturn, .enter: open()
        case .delete: model.goUp()
        case .help: model.toggleMarkAndAdvance()
        case .tab, .backTab: onCommand?(.switchPanel)
        default:
            guard let number = Self.functionKeys.firstIndex(of: key) else { return false }
            onCommand?(.functionKey(number + 1, shifted: shifted))
        }
        return true
    }

    private func extendOrMove(_ delta: Int, shifted: Bool) {
        if shifted { model.toggleMarkAndAdvance() } else { model.moveCursor(by: delta) }
    }

    private func handleSearch(_ event: NSEvent) -> Bool {
        let text = model.searchText ?? ""
        if event.keyCode == 53 || event.specialKey == .carriageReturn {
            let enter = event.specialKey == .carriageReturn
            model.endSearch()
            if enter { open() }
            return true
        }
        if event.specialKey == .delete {
            model.updateSearch(String(text.dropLast()))
            return true
        }
        if event.specialKey == nil, let characters = event.characters, !event.modifierFlags.contains(.command), !characters.unicodeScalars.contains(where: { $0.value < 32 }) {
            model.updateSearch(text + characters)
            return true
        }
        return false
    }

    private static let functionKeys: [NSEvent.SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10]
}
