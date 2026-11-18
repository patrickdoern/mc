import AppKit
import MCCore

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((EditorWindowController) -> Void)?

    private let fileSystem: FileSystem
    private let path: String
    private let readOnly: Bool
    private var encoding: String.Encoding
    private var rawData: Data
    private var isHex = false
    private var textBeforeHex = ""
    private var wraps = false
    private var searchUsesRegex = false
    private var searchIsCaseSensitive = false
    private let permissions: UInt16
    private let textView = EditorTextView()
    private var blockRange: NSRange?
    private var blockAnchor: Int?
    private var lastSearch = ""
    private var lastReplacement = ""
    private var language: String?
    private let markup: MarkupKind?
    private var sourceText: String
    private var isRendered = false
    private var wrapBeforePreview = false

    var hasUnsavedChanges: Bool { window?.isDocumentEdited ?? false }

    init(fileSystem: FileSystem, path: String, data: Data, permissions: UInt16, readOnly: Bool) {
        let (text, encoding) = Self.decode(data)
        self.fileSystem = fileSystem
        self.path = path
        self.readOnly = readOnly
        self.rawData = data
        self.encoding = encoding
        self.permissions = permissions
        self.sourceText = text
        markup = readOnly ? MarkupKind.kind(forFile: PosixPath.name(path)) : nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.title = PosixPath.name(path) + (readOnly ? " (nur lesen)" : "")
        window.representedFilename = fileSystem is LocalFileSystem ? path : ""
        window.minSize = NSSize(width: 720, height: 320)
        window.setFrameAutosaveName("EditorWindow")
        window.tabbingMode = .disallowed
        configureText(text)
        language = text.utf16.count <= SyntaxHighlighter.maximumLength ? SyntaxHighlighter.languageName(forFile: PosixPath.name(path), firstLine: String(text.prefix { $0 != "\n" })) : nil
        applyHighlighting()
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        let keyBar = KeyBar(
            labels: readOnly ? ["Hilfe", "Umbruch", "Ende", "Hex", "Gehe zu", "", "Suchen", "Codierung", markup == nil ? "" : "Vorschau", "Ende"] : ["Hilfe", "Sichern", "Markieren", "Ersetzen", "Kopieren", "Verschieben", "Suchen", "Löschen", "", "Ende"],
            shortLabels: readOnly ? ["Hilfe", "Umbr", "Ende", "Hex", "Gehe", "", "Suche", "Codg", markup == nil ? "" : "Vorsch", "Ende"] : ["Hilfe", "Sichrn", "Markr", "Ersetz", "Kopie", "Versch", "Suche", "Lösch", "", "Ende"]
        ) { [weak self] number in
            self?.perform(functionKey: number, shifted: false)
        }
        let stack = NSStackView(views: [scroll, keyBar])
        stack.orientation = .vertical
        stack.spacing = 0
        window.contentView = stack
        window.makeFirstResponder(textView)
        if markup != nil { showPreview() }
        textView.setSelectedRange(NSRange(location: 0, length: 0))
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
        textView.extraTrailingWidth = 24
        textView.onFunctionKey = { [weak self] number, shifted in self?.perform(functionKey: number, shifted: shifted) ?? false }
        textView.onDeleteLine = { [weak self] in self?.deleteLine(nil) }
        textView.onEscape = { [weak self] in self?.window?.performClose(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
    }

    @objc private func themeDidChange(_ notification: Notification) {
        textView.applyEditorStyle()
        textView.enclosingScrollView?.backgroundColor = Theme.background
        if isRendered { showPreview() } else { applyHighlighting() }
    }

    @objc private func textDidChange(_ notification: Notification) {
        window?.isDocumentEdited = true
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyHighlighting), object: nil)
        perform(#selector(applyHighlighting), with: nil, afterDelay: 0.3)
    }

    @objc private func applyHighlighting() {
        guard !isRendered, let language, let storage = textView.textStorage, storage.length <= SyntaxHighlighter.maximumLength else { return }
        let tokens = SyntaxHighlighter.tokens(in: storage.string, language: language)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: Theme.editorText, range: NSRange(location: 0, length: storage.length))
        for token in tokens { storage.addAttribute(.foregroundColor, value: Theme.syntaxColor(token.kind), range: token.range) }
        storage.endEditing()
    }

    @discardableResult
    private func perform(functionKey number: Int, shifted: Bool) -> Bool {
        switch (number, shifted) {
        case (1, _): showHelp()
        case (2, _) where readOnly: toggleWrap(nil)
        case (2, _): saveDocument(nil)
        case (3, _) where readOnly: window?.performClose(nil)
        case (3, _): toggleBlock()
        case (4, _) where readOnly: toggleHex(nil)
        case (4, _): replaceText(nil)
        case (5, _) where readOnly: goToLine(nil)
        case (5, _): copyBlock()
        case (6, _) where !readOnly: moveBlock()
        case (7, false): findText(nil)
        case (7, true): findNext(nil)
        case (8, _) where readOnly: chooseEncoding(nil)
        case (8, _): deleteBlock()
        case (9, _) where readOnly && markup != nil: togglePreview(nil)
        case (10, _): window?.performClose(nil)
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
        rawData = data
        window?.isDocumentEdited = false
        return true
    }

    @objc func findText(_ sender: Any?) {
        guard let input = Dialogs.searchForm(title: "Suchen", fields: [("Suchen:", lastSearch)], checks: [("Regulärer Ausdruck", searchUsesRegex), ("Groß-/Kleinschreibung beachten", searchIsCaseSensitive)], confirm: "Suchen") else { return }
        guard !input.values[0].isEmpty else { return }
        lastSearch = input.values[0]
        searchUsesRegex = input.checks[0]
        searchIsCaseSensitive = input.checks[1]
        findNext(nil)
    }

    private func expression() -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: searchUsesRegex ? lastSearch : NSRegularExpression.escapedPattern(for: lastSearch), options: searchIsCaseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive])
        } catch {
            Dialogs.show(error: error)
            return nil
        }
    }

    private func nextMatch(from start: Int) -> NSTextCheckingResult? {
        guard let regex = expression() else { return nil }
        let text = textView.string
        let length = (text as NSString).length
        return regex.firstMatch(in: text, range: NSRange(location: start, length: length - start)) ?? regex.firstMatch(in: text, range: NSRange(location: 0, length: length))
    }

    @objc func findNext(_ sender: Any?) {
        guard !lastSearch.isEmpty else { return findText(nil) }
        guard let match = nextMatch(from: textView.selectedRange().upperBound) else { return NSSound.beep() }
        textView.setSelectedRange(match.range)
        textView.scrollRangeToVisible(match.range)
    }

    @objc func replaceText(_ sender: Any?) {
        guard !readOnly, !isHex, let input = Dialogs.searchForm(
            title: "Ersetzen",
            fields: [("Suchen:", lastSearch), ("Ersetzen durch:", lastReplacement)],
            checks: [("Regulärer Ausdruck ($1 für Gruppen)", searchUsesRegex), ("Groß-/Kleinschreibung beachten", searchIsCaseSensitive), ("Alle ersetzen", true)],
            confirm: "Ersetzen"
        ), !input.values[0].isEmpty else { return }
        lastSearch = input.values[0]
        lastReplacement = input.values[1]
        searchUsesRegex = input.checks[0]
        searchIsCaseSensitive = input.checks[1]
        guard let regex = expression() else { return }
        let template = searchUsesRegex ? lastReplacement : NSRegularExpression.escapedTemplate(for: lastReplacement)
        let text = textView.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        if input.checks[2] {
            let count = regex.numberOfMatches(in: text, range: full)
            guard count > 0, textView.shouldChangeText(in: full, replacementString: nil) else { return NSSound.beep() }
            textView.textStorage?.replaceCharacters(in: full, with: regex.stringByReplacingMatches(in: text, range: full, withTemplate: template))
            textView.didChangeText()
            Dialogs.info(title: "Ersetzen", message: "\(count) Ersetzung\(count == 1 ? "" : "en")")
        } else if let match = nextMatch(from: textView.selectedRange().location) {
            textView.insertText(regex.replacementString(for: match, in: text, offset: 0, template: template), replacementRange: match.range)
        } else {
            NSSound.beep()
        }
    }

    @objc func toggleWrap(_ sender: Any?) {
        setWrap(!wraps)
    }

    private func setWrap(_ enabled: Bool) {
        wraps = enabled
        textView.extraTrailingWidth = wraps ? 0 : 24
        guard let container = textView.textContainer, let scroll = textView.enclosingScrollView else { return }
        container.widthTracksTextView = wraps
        textView.isHorizontallyResizable = !wraps
        scroll.hasHorizontalScroller = !wraps
        let width = wraps ? scroll.contentSize.width : CGFloat.greatestFiniteMagnitude
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.setFrameSize(NSSize(width: wraps ? scroll.contentSize.width : textView.frame.width, height: textView.frame.height))
    }

    @objc func togglePreview(_ sender: Any?) {
        guard readOnly, markup != nil, !isHex else { return }
        if isRendered { showSource() } else { showPreview() }
    }

    private func showPreview() {
        guard let markup, let rendered = MarkupRenderer.render(sourceText, kind: markup) else { return }
        if !isRendered { wrapBeforePreview = wraps }
        isRendered = true
        setWrap(true)
        textView.textStorage?.setAttributedString(rendered)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        window?.title = PosixPath.name(path) + " (Vorschau)"
    }

    private func showSource() {
        guard isRendered else { return }
        isRendered = false
        setWrap(wrapBeforePreview)
        textView.textStorage?.setAttributedString(NSAttributedString(string: sourceText))
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.editorText]
        textView.applyEditorStyle()
        applyHighlighting()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
        window?.title = PosixPath.name(path) + (readOnly ? " (nur lesen)" : "")
    }

    @objc func toggleHex(_ sender: Any?) {
        guard readOnly else { return }
        showSource()
        isHex.toggle()
        if isHex {
            textBeforeHex = textView.string
            textView.string = HexDump.render(rawData)
            textView.textColor = Theme.editorText
        } else {
            textView.string = textBeforeHex
            applyHighlighting()
        }
        window?.title = PosixPath.name(path) + (isHex ? " (Hex)" : " (nur lesen)")
    }

    @objc func chooseEncoding(_ sender: Any?) {
        guard !isHex else { return }
        showSource()
        guard !hasUnsavedChanges else { return Dialogs.show(error: FileError("Die Codierung lässt sich nur ohne ungespeicherte Änderungen wechseln")) }
        let encodings: [(String, String.Encoding)] = [("UTF-8", .utf8), ("ISO-8859-1 (Latin 1)", .isoLatin1), ("Windows-1252", .windowsCP1252), ("Mac Roman", .macOSRoman), ("UTF-16", .utf16)]
        guard let result = Dialogs.form(title: "Codierung", popup: ("Zeichensatz:", encodings.map(\.0), encodings.firstIndex { $0.1 == encoding } ?? 0), confirm: "Übernehmen") else { return }
        let chosen = encodings[result.choice].1
        guard let text = String(data: rawData, encoding: chosen) else { return Dialogs.show(error: FileError("Die Datei lässt sich nicht als \(encodings[result.choice].0) lesen")) }
        encoding = chosen
        sourceText = text
        let caret = textView.selectedRange().location
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(caret, (text as NSString).length), length: 0))
        applyHighlighting()
        if !readOnly { window?.isDocumentEdited = false }
    }

    @objc func insertFile(_ sender: Any?) {
        guard !readOnly, let text = Dialogs.prompt(title: "Datei einfügen", message: "Pfad der Datei:", value: PosixPath.parent(path) + "/", confirm: "Einfügen") else { return }
        do {
            let data = try fileSystem.readAll(PosixPath.resolve(text, relativeTo: PosixPath.parent(path), home: fileSystem.homePath))
            textView.insertText(Self.decode(data).0, replacementRange: textView.selectedRange())
        } catch {
            Dialogs.show(error: error)
        }
    }

    @objc func saveBlock(_ sender: Any?) {
        let selection = textView.selectedRange()
        guard let range = selection.length > 0 ? selection : blockRange else { return NSSound.beep() }
        guard let text = Dialogs.prompt(title: "Block sichern", message: "Speichern als:", value: PosixPath.parent(path) + "/", confirm: "Sichern") else { return }
        let block = (textView.string as NSString).substring(with: range)
        do {
            try fileSystem.writeAll(block.data(using: encoding) ?? Data(block.utf8), to: PosixPath.resolve(text, relativeTo: PosixPath.parent(path), home: fileSystem.homePath), permissions: permissions)
        } catch {
            Dialogs.show(error: error)
        }
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
        Dialogs.info(title: readOnly ? "Viewer-Tasten" : "Editor-Tasten", message: readOnly
            ? "F2 Zeilenumbruch · F3/F10/Esc Ende · F4 Hex-Ansicht · F5 Gehe zu Zeile · F7 Suchen (⇧F7 weiter) · F8 Codierung wählen · F9 Vorschau/Quelltext (Markdown, HTML)"
            : "F2 Sichern · F3 Block markieren (Anfang/Ende) · F4 Ersetzen (auch Regex) · F5 Block kopieren · F6 Block verschieben · F7 Suchen (⇧F7 weiter) · F8 Block löschen · Ctrl-Y Zeile löschen · F10/Esc Ende · Menü Bearbeiten: Datei einfügen, Block sichern, Codierung")
    }
}

final class EditorTextView: NSTextView {
    var onFunctionKey: ((Int, Bool) -> Bool)?
    var onDeleteLine: (() -> Void)?
    var onEscape: (() -> Void)?
    var extraTrailingWidth: CGFloat = 0

    private static let functionKeys: [NSEvent.SpecialKey] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10]

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if extraTrailingWidth > 0, let visible = enclosingScrollView?.contentSize.width, newSize.width > visible + 0.5 {
            size.width += extraTrailingWidth
        }
        super.setFrameSize(size)
    }

    func applyEditorStyle() {
        font = Theme.font
        textColor = Theme.editorText
        backgroundColor = Theme.background
        insertionPointColor = Theme.editorText
        selectedTextAttributes = [.backgroundColor: Theme.editorSelection]
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
