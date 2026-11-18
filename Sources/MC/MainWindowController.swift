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
    private let body = NSView()
    private var terminal: ShellTerminal?
    private let quickLook = QuickLook()
    private var keyBar: KeyBar?
    var activeFind: FindDialog?
    private var editors: [EditorWindowController] = []
    lazy var runner: OperationRunner = {
        let runner = OperationRunner(window: window!)
        runner.onStatusChange = { [weak self] in self?.commandLine.status = $0 }
        return runner
    }()

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
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("MainWindow")
        window.tabbingMode = .disallowed
        panelStack.orientation = .horizontal
        panelStack.distribution = .fillEqually
        panelStack.spacing = 0
        let keyBar = KeyBar(
            labels: ["Hilfe", "Menü", "Ansicht", "Bearbeiten", "Kopieren", "Verschieben", "Mkdir", "Löschen", "Menüs", "Beenden"],
            shortLabels: ["Hilfe", "Menü", "Zeige", "Edit", "Kopie", "Versch", "MkDir", "Lösch", "Menüs", "Ende"]
        ) { [weak self] number in
            self?.performFunctionKey(number, shifted: false)
        }
        let menuLine = MenuLineView(titles: ["Links", "Datei", "Befehl", "Optionen", "Rechts"]) { [unowned self] index in menu(at: index) }
        self.menuLine = menuLine
        self.keyBar = keyBar
        let promptLine = ShellInputView(commandLine: commandLine) { [unowned self] in prompt }
        self.promptLine = promptLine
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(panelStack)
        pin(panelStack, to: body)
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        let content = NSStackView(views: [menuLine, body, promptLine, keyBar])
        content.orientation = .vertical
        content.spacing = 0
        window.contentView = content
        for panel in panels {
            panelStack.addArrangedSubview(panel)
            panel.onCommand = { [weak self, weak panel] command in
                guard let self, let panel else { return }
                self.handle(command, from: panel)
            }
            panel.model.onFailure = { error in RunLoop.main.perform(inModes: [.common]) { Dialogs.show(error: error) } }
            panel.peer = { [unowned self, unowned panel] in panels.first { $0 !== panel }!.model }
            let redraw = panel.model.onChange
            panel.model.onChange = { [weak self] in
                redraw?()
                promptLine.needsDisplay = true
                self?.panels.forEach { $0.refreshPreview(); if $0.mode != .list { $0.needsDisplay = true } }
                self?.refreshQuickLook()
            }
            panel.model.reload()
        }
        applyLayout()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
        for (side, panel) in zip(["left", "right"], panels) {
            panel.setMode(PanelMode(rawValue: defaults.integer(forKey: side + "Mode")) ?? .list)
        }
        let preferred = panels[min(max(defaults.integer(forKey: "activePanel"), 0), 1)]
        let focusable = [preferred] + panels.filter { $0 !== preferred }
        let start = focusable.first { $0.mode == .list || $0.mode == .tree } ?? panels[0]
        activate(start)
        window.makeFirstResponder(start)
        panels.forEach { $0.onModeChange = { [weak self] in self?.saveState() } }
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
            defaults.set(panel.mode.rawValue, forKey: side + "Mode")
        }
        defaults.set(activePanel.model.showHidden, forKey: "showHidden")
        defaults.set(panels.firstIndex { $0 === activePanel } ?? 0, forKey: "activePanel")
    }

    private func pin(_ view: NSView, to container: NSView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    func applyLayout() {
        panelStack.orientation = Settings.verticalLayout ? .vertical : .horizontal
        menuLine?.isHidden = !Settings.showMenuLine
        promptLine?.isHidden = !Settings.showCommandLine || terminal?.isHidden == false
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
        saveState()
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
        case .complete: completeCommand()
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
        if model.isLocal, let command = FileActions.command(for: entry.name, kind: "open") {
            launch(command, for: entry.name, in: model)
        } else if model.isLocal, ArchiveFileSystem.isArchive(entry.name) {
            enterArchive(model.fullPath(of: entry.name), in: model)
        } else if model.isLocal {
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
        guard let text = Dialogs.prompt(title: verb, message: "\(verb) \(subject) nach (Maske möglich, z. B. *.bak):", value: proposal, confirm: verb) else { return }
        let resolved = PosixPath.resolve(text, relativeTo: target.path, home: target.fileSystem.homePath)
        let mask = NameMask.isMask(PosixPath.name(resolved)) ? PosixPath.name(resolved) : nil
        let destination = mask == nil ? resolved : PosixPath.parent(resolved)
        let sourceSystem = source.fileSystem
        let targetSystem = target.fileSystem
        let sourceDirectory = source.path
        runner.run(title: verb + " …", { operation in
            let existing = try? targetSystem.stat(destination)
            let intoDirectory = mask != nil || existing?.isDirectory == true || text.hasSuffix("/") || names.count > 1
            if intoDirectory { try targetSystem.makeDirectories(destination) }
            let transfers = names.map { name in
                let targetName = mask.map { NameMask.apply($0, to: PosixPath.name(name)) } ?? PosixPath.name(name)
                return Transfer(source: PosixPath.join(sourceDirectory, name), destination: intoDirectory ? PosixPath.join(destination, targetName) : destination)
            }
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
        if entry.isDirectory {
            _ = model.enterCursor()
        } else if model.isLocal, let command = FileActions.command(for: entry.name, kind: readOnly ? "view" : "edit") {
            launch(command, for: entry.name, in: model)
        } else {
            openEditor(model: model, name: entry.name, readOnly: readOnly)
        }
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
            let data = entry == nil ? Data() : try system.readAll(path)
            DispatchQueue.main.sync {
                loaded.value = EditorWindowController(fileSystem: system, path: path, data: data, permissions: entry?.permissions ?? 0o644, readOnly: readOnly)
            }
        }, completion: { [weak self] in
            guard let self, let editor = loaded.value else { return }
            editor.onClose = { [weak self] closed in
                self?.editors.removeAll { $0 === closed }
                self?.reloadPanels()
            }
            editors.append(editor)
            editor.showWindow(nil)
            if system is LocalFileSystem, !path.hasPrefix(NSTemporaryDirectory() + "moonlight-diff") {
                Settings.viewedFiles = ViewedFiles.recording(ViewedFile(path: path, edited: !readOnly), in: Settings.viewedFiles)
            }
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

    private func completeCommand() {
        let model = activePanel.model
        let completion = CommandCompletion.complete(
            text: commandLine.text, directory: model.path, fileSystem: model.fileSystem,
            home: model.fileSystem.homePath, searchPath: ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        )
        guard !completion.candidates.isEmpty else { return NSSound.beep() }
        if completion.candidates.count == 1 {
            let only = completion.candidates[0]
            commandLine.replaceWord(completion.word, with: only + (only.hasSuffix("/") ? "" : " "))
            return
        }
        commandLine.replaceWord(completion.word, with: completion.commonPrefix)
        let menu = NSMenu()
        for candidate in completion.candidates.prefix(30) {
            menu.addItem(ClosureMenuItem(candidate) { [weak self] in
                self?.commandLine.replaceWord(completion.commonPrefix, with: candidate + (candidate.hasSuffix("/") ? "" : " "))
            })
        }
        popUp(menu, title: "Vervollständigen")
    }

    private func insertCurrentName() {
        guard let entry = activePanel.model.currentEntry, !activePanel.model.isParentRow(activePanel.model.cursor) else { return }
        commandLine.append(Shell.quote(entry.name) + " ")
    }

    func enterArchive(_ path: String, in model: PanelModel) {
        let archive = Box<ArchiveFileSystem>()
        runner.run(title: "Öffne \(PosixPath.name(path)) …", { _ in
            archive.value = try ArchiveFileSystem(path: path)
        }, completion: {
            guard let system = archive.value else { return }
            model.navigate(to: "/", on: system)
        })
    }

    private func launch(_ command: String, for name: String, in model: PanelModel) {
        let other = inactivePanel.model
        let context = UserMenuContext(currentName: name, directory: model.path, selection: model.selectedNames, otherDirectory: other.path, otherName: other.currentEntry?.name ?? "")
        let expanded = UserMenu.expand(command, context: context)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", expanded]
        process.currentDirectoryURL = URL(fileURLWithPath: model.path)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async { Dialogs.show(error: FileError("\(expanded)\n\n\(text)")) }
        }
        do {
            try process.run()
        } catch {
            Dialogs.show(error: error)
        }
    }

    @objc func quickLookFile(_ sender: Any?) {
        let model = activePanel.model
        guard let entry = model.currentEntry, !model.isParentRow(model.cursor), !entry.isDirectory else { return }
        if quickLook.isVisible { return quickLook.hide() }
        if model.isLocal { return quickLook.show(URL(fileURLWithPath: model.fullPath(of: entry.name))) }
        let system = model.fileSystem
        let path = model.fullPath(of: entry.name)
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("moonlight-quicklook").appendingPathComponent(entry.name)
        runner.run(title: "Lade \(entry.name) …", { _ in
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try system.readAll(path).write(to: target)
        }, completion: { [weak self] in
            if FileManager.default.fileExists(atPath: target.path) { self?.quickLook.show(target) }
        })
    }

    @objc func toggleTerminal(_ sender: Any?) {
        if let terminal, !terminal.isHidden { hideTerminal() } else { showTerminal() }
    }

    private func showTerminal() {
        let model = activePanel.model
        if terminal == nil {
            let created = ShellTerminal(directory: model.isLocal ? model.path : NSHomeDirectory())
            created.onExit = { [weak self] in self?.terminalExited() }
            created.translatesAutoresizingMaskIntoConstraints = false
            body.addSubview(created)
            pin(created, to: body)
            terminal = created
        }
        panelStack.isHidden = true
        terminal?.isHidden = false
        applyLayout()
        window?.makeFirstResponder(terminal)
    }

    private func hideTerminal() {
        terminal?.isHidden = true
        panelStack.isHidden = false
        applyLayout()
        window?.makeFirstResponder(activePanel)
        reloadPanels()
    }

    private func terminalExited() {
        terminal?.removeFromSuperview()
        terminal = nil
        panelStack.isHidden = false
        applyLayout()
        window?.makeFirstResponder(activePanel)
        reloadPanels()
    }

    func runInTerminal(_ command: String, in directory: String) {
        showTerminal()
        terminal?.run(command, in: directory)
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
        runInTerminal(command, in: model.path)
    }

    private func refreshQuickLook() {
        let model = activePanel.model
        guard quickLook.isVisible, model.isLocal, let entry = model.currentEntry, !model.isParentRow(model.cursor), !entry.isDirectory else { return }
        quickLook.update(URL(fileURLWithPath: model.fullPath(of: entry.name)))
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
        Tippen schreibt in die Kommandozeile · Tab vervollständigt · Enter führt im Terminal aus · ⌘Enter fügt Dateinamen ein · Ctrl-P/N Verlauf
        Ctrl-O Terminal ein/aus · ⌘Y Quick Look · F6/⇧F6 mit Maske, z. B. *.bak · Enter auf Archiv öffnet es als Ordner
        Hinweis: Die F-Tasten brauchen „F1, F2 usw. als Standardfunktionstasten“ oder die Fn-Taste.
        """)
    }
}

final class Box<Value> {
    var value: Value?
}
