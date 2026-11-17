import AppKit
import MCCore

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((EditorWindowController) -> Void)?

    private let fileSystem: FileSystem
    private let path: String
    private let readOnly: Bool
    private let encoding: String.Encoding
    private let permissions: UInt16
    private let textView = EditorTextView()
    private var blockRange: NSRange?
    private var blockAnchor: Int?
    private var lastSearch = ""
    private var lastReplacement = ""

    var hasUnsavedChanges: Bool { window?.isDocumentEdited ?? false }

    init(fileSystem: FileSystem, path: String, text: String, encoding: String.Encoding, permissions: UInt16, readOnly: Bool) {
        self.fileSystem = fileSystem
        self.path = path
        self.readOnly = readOnly
        self.encoding = encoding
        self.permissions = permissions
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.title = PosixPath.name(path) + (readOnly ? " (nur lesen)" : "")
        window.representedFilename = fileSystem is LocalFileSystem ? path : ""
        window.setFrameAutosaveName("EditorWindow")
        window.tabbingMode = .disallowed
        configureText(text)
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        let keyBar = KeyBar(labels: readOnly ? ["Hilfe", "", "", "", "", "", "Suchen", "", "", "Ende"] : ["Hilfe", "Sichern", "Markier", "Ersetz", "Kopier", "Versch", "Suchen", "Lösch", "", "Ende"]) { [weak self] number in
            self?.perform(functionKey: number, shifted: false)
        }
        let stack = NSStackView(views: [scroll, keyBar])
        stack.orientation = .vertical
        stack.spacing = 0
        window.contentView = stack
        window.makeFirstResponder(textView)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func decode(_ data: Data) -> (String, String.Encoding) {
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        return (String(data.map { Character(UnicodeScalar($0)) }), .isoLatin1)
    }

    private func configureText(_ text: String) {
        textView.string = text
        textView.applyEditorStyle()
        textView.isEditable = !readOnly
        textView.allowsUndo = true
        textView.onFunctionKey = { [weak self] number, shifted in self?.perform(functionKey: number, shifted: shifted) ?? false }
        textView.onDeleteLine = { [weak self] in self?.deleteLine(nil) }
        textView.onEscape = { [weak self] in self?.close() }
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
    }

    @objc private func themeDidChange(_ notification: Notification) {
        textView.applyEditorStyle()
        textView.enclosingScrollView?.backgroundColor = Theme.background
    }

    @objc private func textDidChange(_ notification: Notification) {
        window?.isDocumentEdited = true
    }

    @discardableResult
    private func perform(functionKey number: Int, shifted: Bool) -> Bool {
        switch (number, shifted) {
        case (1, _): showHelp()
        case (2, _) where !readOnly: saveDocument(nil)
        case (3, _) where !readOnly: toggleBlock()
        case (4, _) where !readOnly: replaceText(nil)
        case (5, _) where !readOnly: copyBlock()
        case (6, _) where !readOnly: moveBlock()
        case (7, false): findText(nil)
        case (7, true): findNext(nil)
        case (8, _) where !readOnly: deleteBlock()
        case (10, _): close()
        default: return false
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasUnsavedChanges else { return true }
        switch Dialogs.askToSave(name: PosixPath.name(path)) {
        case .alertFirstButtonReturn:
            return save()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    @objc func saveDocument(_ sender: Any?) {
        save()
    }

    @discardableResult
    private func save() -> Bool {
        let data = textView.string.data(using: encoding, allowLossyConversion: false) ?? Data(textView.string.utf8)
        do {
            try fileSystem.writeAll(data, to: path, permissions: permissions)
        } catch {
            Dialogs.show(error: error)
            return false
        }
        window?.isDocumentEdited = false
        return true
    }

    @objc func findText(_ sender: Any?) {
        guard let term = Dialogs.prompt(title: "Suchen", message: "Suchbegriff:", value: lastSearch, confirm: "Suchen") else { return }
        lastSearch = term
        findNext(nil)
    }

    @objc func findNext(_ sender: Any?) {
        guard !lastSearch.isEmpty else { return findText(nil) }
        let text = textView.string as NSString
        let start = textView.selectedRange().upperBound
        var found = text.range(of: lastSearch, options: .caseInsensitive, range: NSRange(location: start, length: text.length - start))
        if found.location == NSNotFound { found = text.range(of: lastSearch, options: .caseInsensitive) }
        guard found.location != NSNotFound else { return NSSound.beep() }
        textView.setSelectedRange(found)
        textView.scrollRangeToVisible(found)
    }

    @objc func replaceText(_ sender: Any?) {
        guard !readOnly, let term = Dialogs.prompt(title: "Ersetzen", message: "Suchbegriff:", value: lastSearch, confirm: "Weiter") else { return }
        guard let replacement = Dialogs.prompt(title: "Ersetzen", message: "\(term) ersetzen durch:", value: lastReplacement, confirm: "Alle ersetzen") else { return }
        lastSearch = term
        lastReplacement = replacement
        let updated = textView.string.replacingOccurrences(of: term, with: replacement, options: .caseInsensitive)
        guard updated != textView.string, textView.shouldChangeText(in: NSRange(location: 0, length: (textView.string as NSString).length), replacementString: updated) else { return NSSound.beep() }
        textView.textStorage?.replaceCharacters(in: NSRange(location: 0, length: textView.textStorage?.length ?? 0), with: updated)
        textView.didChangeText()
    }

    @objc func goToLine(_ sender: Any?) {
        guard let value = Dialogs.prompt(title: "Gehe zu Zeile", message: "Zeilennummer:", confirm: "Gehen"), let line = Int(value), line > 0 else { return }
        let text = textView.string as NSString
        var location = 0
        for _ in 1..<line {
            let next = NSMaxRange(text.lineRange(for: NSRange(location: location, length: 0)))
            if next >= text.length { break }
            location = next
        }
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.scrollRangeToVisible(NSRange(location: location, length: 0))
    }

    @objc func deleteLine(_ sender: Any?) {
        guard !readOnly else { return }
        let range = (textView.string as NSString).lineRange(for: textView.selectedRange())
        textView.insertText("", replacementRange: range)
    }

    private func toggleBlock() {
        let caret = textView.selectedRange().location
        guard let anchor = blockAnchor else {
            blockAnchor = caret
            blockRange = nil
            return
        }
        let range = NSRange(location: min(anchor, caret), length: abs(caret - anchor))
        blockRange = range.length > 0 ? range : nil
        blockAnchor = nil
        if range.length > 0 { textView.setSelectedRange(range) }
    }

    private func copyBlock() {
        guard let range = blockRange else { return NSSound.beep() }
        let text = (textView.string as NSString).substring(with: range)
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    private func moveBlock() {
        guard let range = blockRange else { return NSSound.beep() }
        let text = (textView.string as NSString).substring(with: range)
        var caret = textView.selectedRange().location
        if NSLocationInRange(caret, range) { return NSSound.beep() }
        textView.insertText("", replacementRange: range)
        if caret > range.location { caret -= range.length }
        textView.insertText(text, replacementRange: NSRange(location: caret, length: 0))
        blockRange = NSRange(location: caret, length: range.length)
    }

    private func deleteBlock() {
        guard let range = blockRange else { return NSSound.beep() }
        textView.insertText("", replacementRange: range)
        blockRange = nil
    }

    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Editor-Tasten"
        alert.informativeText = "F2 Sichern · F3 Block markieren (Anfang/Ende) · F4 Ersetzen · F5 Block kopieren · F6 Block verschieben · F7 Suchen · ⇧F7 Weitersuchen · F8 Block löschen · Ctrl-Y Zeile löschen · F10/Esc Beenden"
        alert.runModal()
    }
}

final class EditorTextView: NSTextView {
    var onFunctionKey: ((Int, Bool) -> Bool)?
    var onDeleteLine: (() -> Void)?
    var onEscape: (() -> Void)?

    private static let functionKeys: [NSEvent.SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10]

    func applyEditorStyle() {
        font = Theme.font
        textColor = Theme.editorText
        backgroundColor = Theme.background
        insertionPointColor = .white
        selectedTextAttributes = [.backgroundColor: Theme.editorSelection, .foregroundColor: NSColor.white]
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isHorizontallyResizable = true
        isVerticallyResizable = true
        autoresizingMask = [.width, .height]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 4, height: 4)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let key = event.specialKey, let index = Self.functionKeys.firstIndex(of: key), onFunctionKey?(index + 1, modifiers.contains(.shift)) == true { return }
        if event.keyCode == 53 { return onEscape?() ?? () }
        if modifiers == .control, event.charactersIgnoringModifiers == "y" { return onDeleteLine?() ?? () }
        super.keyDown(with: event)
    }
}
