import AppKit
import MCCore

final class MainWindowController: NSWindowController {
    private static let connectionHistoryKey = "sftpHistory"

    private let interaction = DialogInteraction()
    let panelStack = NSStackView()
    let commandLine: ShellInput
    private var panels: [PanelView]
    var panelViews: [PanelView] { panels }
    private(set) var activePanel: PanelView
    private var menuLine: MenuLineView?
    private var promptLine: ShellInputView?
    private var keyBar: KeyBar?
    var finders: [FindWindowController] = []
    private var outputs: [CommandOutputWindowController] = []
    private var editors: [EditorWindowController] = []
    lazy var runner = OperationRunner(window: window!)

    var hasUnsavedEditors: Bool { editors.contains(where: \.hasUnsavedChanges) }

    init(startPaths: [String]) {
        let commandLine = ShellInput()
        self.commandLine = commandLine
        let defaults = UserDefaults.standard
        let showHidden = defaults.bool(forKey: "showHidden")
        panels = ["left", "right"].enumerated().map { index, side in
            let saved = index < startPaths.count ? startPaths[index] : defaults.string(forKey: side + "Path")
            var isDirectory: ObjCBool = false
            let path = saved.flatMap { FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue ? $0 : nil } ?? NSHomeDirectory()
            let key = SortKey(rawValue: defaults.integer(forKey: side + "SortKey")) ?? .name
            let ascending = defaults.object(forKey: side + "SortAscending") as? Bool ?? true
            return PanelView(model: PanelModel(fileSystem: LocalFileSystem.shared, path: path, sortKey: key, ascending: ascending, showHidden: showHidden,
                dirsFirst: defaults.object(forKey: side + "DirsFirst") as? Bool ?? true,
                caseSensitive: defaults.bool(forKey: side + "CaseSensitive"),
                format: ListFormat(rawValue: defaults.integer(forKey: side + "Format")) ?? .full), commandLine: commandLine)
        }
        activePanel = panels[0]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Moonlight Commander"
        window.minSize = NSSize(width: 640, height: 360)
        window.setFrameAutosaveName("MainWindow")
        window.tabbingMode = .disallowed
        panelStack.orientation = .horizontal
        panelStack.distribution = .fillEqually
        panelStack.spacing = 0
        let keyBar = KeyBar(labels: ["Hilfe", "Menü", "Ansicht", "Bearbeiten", "Kopieren", "Verschieben", "Mkdir", "Löschen", "Menüs", "Beenden"]) { [weak self] number in
            self?.performFunctionKey(number, shifted: false)
        }
        let menuLine = MenuLineView(titles: ["Links", "Datei", "Befehl", "Optionen", "Rechts"]) { [unowned self] index in menu(at: index) }
        self.menuLine = menuLine
        self.keyBar = keyBar
        let promptLine = ShellInputView(commandLine: commandLine) { [unowned self] in prompt }
        self.promptLine = promptLine
        let content = NSStackView(views: [menuLine, panelStack, promptLine, keyBar])
        content.orientation = .vertical
        content.spacing = 0
        window.contentView = content
        for panel in panels {
            panelStack.addArrangedSubview(panel)
            panel.onCommand = { [weak self, weak panel] command in
                guard let self, let panel else { return }
                self.handle(command, from: panel)
            }
            panel.model.onFailure = { Dialogs.show(error: $0) }
            panel.peer = { [unowned self, unowned panel] in panels.first { $0 !== panel }!.model }
            let redraw = panel.model.onChange
            panel.model.onChange = { [weak self] in
                redraw?()
                promptLine.needsDisplay = true
                self?.panels.forEach { $0.refreshPreview(); if $0.mode != .list { $0.needsDisplay = true } }
            }
            panel.model.reload()
        }
        applyLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
        activate(panels[0])
        window.makeFirstResponder(panels[0])
    }

    required init?(coder: NSCoder) { fatalError() }

    func saveState() {
        let defaults = UserDefaults.standard
        for (side, panel) in zip(["left", "right"], panels) {
            let model = panel.model
            if model.isLocal { defaults.set(model.path, forKey: side + "Path") }
            defaults.set(model.sortKey.rawValue, forKey: side + "SortKey")
            defaults.set(model.ascending, forKey: side + "SortAscending")
            defaults.set(model.dirsFirst, forKey: side + "DirsFirst")
            defaults.set(model.caseSensitive, forKey: side + "CaseSensitive")
            defaults.set(model.format.rawValue, forKey: side + "Format")
        }
        defaults.set(activePanel.model.showHidden, forKey: "showHidden")
    }

    func applyLayout() {
        panelStack.orientation = Settings.verticalLayout ? .vertical : .horizontal
        menuLine?.isHidden = !Settings.showMenuLine
        promptLine?.isHidden = !Settings.showCommandLine
        keyBar?.isHidden = !Settings.showKeyBar
    }

    @objc private func themeDidChange(_ notification: Notification) {
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        window?.contentView.map(redraw)
    }

    var inactivePanel: PanelView { panels.first { $0 !== activePanel }! }

    func activate(_ panel: PanelView) {
        activePanel = panel
        panels.forEach { $0.isActive = $0 === panel }
        commandLine.onChange?()
    }

    private func handle(_ command: PanelCommand, from panel: PanelView) {
        switch command {
        case .activate: activate(panel)
        case .switchPanel:
            if inactivePanel.mode == .list || inactivePanel.mode == .tree { window?.makeFirstResponder(inactivePanel) }
        case .functionKey(let number, let shifted): performFunctionKey(number, shifted: shifted)
        case .openFile(let entry): open(entry, in: panel.model)
        case .markPattern(let select): markPattern(select: select)
        case .execute: executeCommand()
        case .insertName: insertCurrentName()
        }
    }

    private func performFunctionKey(_ number: Int, shifted: Bool) {
        switch (number, shifted) {
        case (1, _): showHelp()
        case (2, _): userMenu(nil)
        case (3, _): viewFile(nil)
        case (4, false): editFile(nil)
        case (4, true): newFile(nil)
        case (5, _): copyFiles(nil)
        case (6, false): moveFiles(nil)
        case (6, true): renameFile(nil)
        case (7, _): makeDirectory(nil)
        case (8, false): deleteFiles(nil)
        case (8, true): deleteFilesPermanently(nil)
        case (9, _): menuLine?.open(0)
        default: NSApp.terminate(nil)
        }
    }

    func edit(path: String) {
        openEditor(system: LocalFileSystem.shared, path: path, readOnly: false)
        NSApp.activate(ignoringOtherApps: true)
    }

    func open(paths: [String]) {
        let targets = paths.map { path -> (directory: String, name: String?) in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return isDirectory.boolValue ? (path, nil) : (PosixPath.parent(path), PosixPath.name(path))
        }
        let destinations = targets.count >= 2 ? panels : [activePanel]
        for (panel, target) in zip(destinations, targets) {
            panel.model.navigate(to: target.directory, on: LocalFileSystem.shared, selecting: target.name)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func open(_ entry: FileEntry, in model: PanelModel) {
        if model.isLocal {
            NSWorkspace.shared.open(URL(fileURLWithPath: model.fullPath(of: entry.name)))
        } else {
            openEditor(model: model, name: entry.name, readOnly: true)
        }
    }

    @objc func connect(_ sender: Any?) {
        let history = UserDefaults.standard.stringArray(forKey: Self.connectionHistoryKey) ?? []
        guard let text = Dialogs.prompt(title: "SFTP-Verbindung", message: "user@host[:port][/pfad] oder SSH-Alias:", value: history.first ?? "", confirm: "Verbinden", history: history),
              let target = SSHTarget.parse(text) else { return }
        let model = activePanel.model
        let interaction = interaction
        let connection = Box<SFTPFileSystem>()
        runner.run(title: "Verbinde mit \(target.displayName) …", { _ in
            connection.value = try SFTPFileSystem(settings: try SSHSettings.resolve(target), interaction: interaction)
        }, completion: {
            guard let system = connection.value else { return }
            UserDefaults.standard.set(([text] + history.filter { $0 != text }).prefix(10).map { $0 }, forKey: Self.connectionHistoryKey)
            model.navigate(to: target.path ?? system.homePath, on: system)
        })
    }

    @objc func copyFiles(_ sender: Any?) { transfer(move: false, inPlace: false) }
    @objc func moveFiles(_ sender: Any?) { transfer(move: true, inPlace: false) }
    @objc func renameFile(_ sender: Any?) { transfer(move: true, inPlace: true) }

    private func transfer(move: Bool, inPlace: Bool) {
        let source = activePanel.model
        let target = inPlace ? source : inactivePanel.model
        let names = source.selectedNames
        guard !names.isEmpty else { return }
        let verb = inPlace ? "Umbenennen" : move ? "Verschieben" : "Kopieren"
        let subject = names.count == 1 ? "„\(names[0])“" : "\(names.count) Objekte"
        let proposal = inPlace ? names[0] : PosixPath.join(target.path, "")
        guard let text = Dialogs.prompt(title: verb, message: "\(verb) \(subject) nach:", value: proposal, confirm: verb) else { return }
        let destination = PosixPath.resolve(text, relativeTo: target.path, home: target.fileSystem.homePath)
        let sourceSystem = source.fileSystem
        let targetSystem = target.fileSystem
        let sourceDirectory = source.path
        runner.run(title: verb + " …", { operation in
            let existing = try? targetSystem.stat(destination)
            let intoDirectory = existing?.isDirectory == true || text.hasSuffix("/") || names.count > 1
            if intoDirectory { try targetSystem.makeDirectories(destination) }
            let transfers = names.map { Transfer(source: PosixPath.join(sourceDirectory, $0), destination: intoDirectory ? PosixPath.join(destination, $0) : destination) }
            if move {
                try operation.move(transfers, from: sourceSystem, to: targetSystem)
            } else {
                try operation.copy(transfers, from: sourceSystem, to: targetSystem)
            }
        }, completion: { [weak self] in
            source.clearMarks()
            self?.reloadPanels()
        })
    }

    @objc func deleteFiles(_ sender: Any?) { delete(permanently: false) }
    @objc func deleteFilesPermanently(_ sender: Any?) { delete(permanently: true) }

    private func delete(permanently: Bool) {
        let model = activePanel.model
        let names = model.selectedNames
        guard !names.isEmpty else { return }
        let trash = model.isLocal && !permanently && Settings.useTrash
        let subject = names.count == 1 ? "„\(names[0])“" : "\(names.count) Objekte"
        let confirmed = (trash && !Settings.confirmDelete) || Dialogs.confirm(
            title: trash ? "In den Papierkorb legen?" : "Endgültig löschen?",
            message: trash ? subject : "\(subject) wird unwiderruflich gelöscht.",
            confirm: trash ? "In den Papierkorb" : "Löschen",
            destructive: !trash
        )
        guard confirmed else { return }
        let system = model.fileSystem
        let paths = names.map(model.fullPath(of:))
        runner.run(title: "Lösche …", { operation in
            try operation.delete(paths, on: system, trash: trash)
        }, completion: { [weak self] in
            model.clearMarks()
            self?.reloadPanels()
        })
    }

    @objc func makeDirectory(_ sender: Any?) {
        let model = activePanel.model
        guard let text = Dialogs.prompt(title: "Neuer Ordner", message: "Name des Ordners:", confirm: "Anlegen") else { return }
        let path = PosixPath.resolve(text, relativeTo: model.path, home: model.fileSystem.homePath)
        let system = model.fileSystem
        runner.run(title: "Lege Ordner an …", { _ in try system.makeDirectories(path) }, completion: { [weak self] in
            model.reload(selecting: text.split(separator: "/").first.map(String.init))
            self?.reloadOtherPanel()
        })
    }

    @objc func viewFile(_ sender: Any?) { openCurrent(readOnly: true) }
    @objc func editFile(_ sender: Any?) { openCurrent(readOnly: false) }

    @objc func newFile(_ sender: Any?) {
        let model = activePanel.model
        guard let name = Dialogs.prompt(title: "Neue Datei", message: "Dateiname:", confirm: "Bearbeiten") else { return }
        openEditor(model: model, name: name, readOnly: false)
    }

    private func openCurrent(readOnly: Bool) {
        let model = activePanel.model
        guard let entry = model.currentEntry, !model.isParentRow(model.cursor) else { return }
        if entry.isDirectory { _ = model.enterCursor() } else { openEditor(model: model, name: entry.name, readOnly: readOnly) }
    }

    private func openEditor(model: PanelModel, name: String, readOnly: Bool) {
        openEditor(system: model.fileSystem, path: model.fullPath(of: name), readOnly: readOnly)
    }

    func openEditor(system: FileSystem, path: String, readOnly: Bool) {
        let name = PosixPath.name(path)
        let loaded = Box<EditorWindowController>()
        runner.run(title: "Lade \(name) …", { _ in
            let entry = try? system.stat(path)
            if let entry, entry.size > 50_000_000 { throw FileError("\(name) ist zu groß für den Editor (über 50 MB)") }
            let (text, encoding) = entry == nil ? ("", String.Encoding.utf8) : EditorWindowController.decode(try system.readAll(path))
            DispatchQueue.main.sync {
                loaded.value = EditorWindowController(fileSystem: system, path: path, text: text, encoding: encoding, permissions: entry?.permissions ?? 0o644, readOnly: readOnly)
            }
        }, completion: { [weak self] in
            guard let self, let editor = loaded.value else { return }
            editor.onClose = { [weak self] closed in
                self?.editors.removeAll { $0 === closed }
                self?.reloadPanels()
            }
            editors.append(editor)
            editor.showWindow(nil)
        })
    }

    @objc func refresh(_ sender: Any?) {
        activePanel.model.reload()
    }

    @objc func swapPanels(_ sender: Any?) {
        panels.reverse()
        panelStack.arrangedSubviews.forEach(panelStack.removeArrangedSubview)
        panels.forEach(panelStack.addArrangedSubview)
    }

    @objc func toggleHidden(_ sender: Any?) {
        panels.forEach { $0.model.toggleHidden() }
    }

    @objc func sortByName(_ sender: Any?) { activePanel.model.sort(by: .name) }
    @objc func sortByExtension(_ sender: Any?) { activePanel.model.sort(by: .fileExtension) }
    @objc func sortBySize(_ sender: Any?) { activePanel.model.sort(by: .size) }
    @objc func sortByDate(_ sender: Any?) { activePanel.model.sort(by: .date) }

    @objc func goToPath(_ sender: Any?) {
        let model = activePanel.model
        guard let text = Dialogs.prompt(title: "Gehe zu", message: "Pfad:", value: model.path, confirm: "Gehen") else { return }
        model.navigate(to: PosixPath.resolve(text, relativeTo: model.path, home: model.fileSystem.homePath))
    }

    @objc func goHome(_ sender: Any?) {
        activePanel.model.navigate(to: NSHomeDirectory(), on: LocalFileSystem.shared)
    }

    func markPattern(select: Bool) {
        guard let pattern = Dialogs.prompt(title: select ? "Auswählen" : "Abwählen", message: "Muster (z. B. *.txt):", value: "*", confirm: "OK") else { return }
        activePanel.model.mark(matching: pattern, select: select)
    }

    private var prompt: String {
        let model = activePanel.model
        guard model.isLocal else { return model.title }
        return model.path.hasPrefix(NSHomeDirectory()) ? "~" + model.path.dropFirst(NSHomeDirectory().count) : model.path
    }

    private func insertCurrentName() {
        guard let entry = activePanel.model.currentEntry, !activePanel.model.isParentRow(activePanel.model.cursor) else { return }
        commandLine.append(Shell.quote(entry.name) + " ")
    }

    func runShell(_ command: String, in directory: String) {
        let output = CommandOutputWindowController(command: command, directory: directory)
        output.onClose = { [weak self] closed in
            self?.outputs.removeAll { $0 === closed }
            self?.reloadPanels()
        }
        outputs.append(output)
        output.showWindow(nil)
    }

    private func executeCommand() {
        let command = commandLine.text.trimmingCharacters(in: .whitespaces)
        if command == "exit" { return NSApp.terminate(nil) }
        commandLine.remember(command)
        commandLine.clear()
        let model = activePanel.model
        if command == "cd" || command.hasPrefix("cd ") {
            let argument = command.dropFirst(2).trimmingCharacters(in: .whitespaces)
            model.navigate(to: PosixPath.resolve(argument.isEmpty ? "~" : argument, relativeTo: model.path, home: model.fileSystem.homePath))
            return
        }
        guard model.isLocal else { return Dialogs.show(error: FileError("Befehle laufen nur in lokalen Ordnern")) }
        runShell(command, in: model.path)
    }

    func reloadPanels() {
        panels.forEach { $0.model.reload() }
    }

    private func reloadOtherPanel() {
        inactivePanel.model.reload()
    }

    private func showHelp() {
        Dialogs.info(title: "Tastenbelegung", message: """
        Tab Panel wechseln · Enter öffnen · Backspace/⌘↑ eine Ebene hoch
        Leertaste/Einfg/⇧↑↓ markieren · + − Muster markieren · * Markierung umkehren
        Ctrl-S Schnellsuche · ⌘L Gehe zu Pfad · ⇧⌘H Home · ⌘K SFTP verbinden
        F3 Anzeigen · F4 Bearbeiten (⇧F4 neue Datei) · F5 Kopieren · F6 Verschieben (⇧F6 Umbenennen)
        F2 Benutzermenü · F7 Ordner anlegen · F8 Löschen (⇧F8 endgültig) · F9 Menüs · F10 Beenden
        Tippen schreibt in die Kommandozeile · Enter führt aus · ⌘Enter fügt Dateinamen ein · Ctrl-P/N Verlauf
        Hinweis: Die F-Tasten brauchen „F1, F2 usw. als Standardfunktionstasten“ oder die Fn-Taste.
        """)
    }
}

private final class Box<Value> {
    var value: Value?
}
