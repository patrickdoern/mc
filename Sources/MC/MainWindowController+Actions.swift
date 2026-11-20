import AppKit
import MCCore

extension MainWindowController {
    private var localSystem: LocalFileSystem { LocalFileSystem.shared }

    private func requireLocal(_ model: PanelModel, _ action: String) -> Bool {
        guard model.isLocal else {
            Dialogs.show(error: FileError("\(action) ist nur im lokalen Dateisystem möglich"))
            return false
        }
        return true
    }

    private func currentFile(_ model: PanelModel) -> FileEntry? {
        guard let entry = model.currentEntry, !model.isParentRow(model.cursor) else { return nil }
        return entry
    }

    @objc func changePermissions(_ sender: Any?) {
        let model = activePanel.model
        let names = model.selectedNames
        guard !names.isEmpty, let entry = model.currentEntry else { return }
        guard let text = Dialogs.prompt(title: "Zugriffsrechte (chmod)", message: "Oktal, z. B. 644 oder 755:", value: String(entry.permissions & 0o777, radix: 8), confirm: "Ändern") else { return }
        guard let mode = UInt16(text, radix: 8) else { return Dialogs.show(error: FileError("Keine gültige Oktalzahl: \(text)")) }
        let system = model.fileSystem
        let paths = names.map(model.fullPath(of:))
        runner.run(title: "Ändere Rechte …", { _ in
            for path in paths { try system.setPermissions(path, mode) }
        }, completion: { [weak self] in self?.reloadPanels() })
    }

    @objc func changeOwner(_ sender: Any?) {
        let model = activePanel.model
        guard requireLocal(model, "Chown"), !model.selectedNames.isEmpty,
              let text = Dialogs.prompt(title: "Besitzer (chown)", message: "benutzer:gruppe (eines davon darf fehlen):", value: NSUserName() + ":staff", confirm: "Ändern") else { return }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let paths = model.selectedNames.map(model.fullPath(of:))
        let system = localSystem
        runner.run(title: "Ändere Besitzer …", { _ in
            for path in paths { try system.setOwner(path, user: parts[0], group: parts.count > 1 ? parts[1] : nil) }
        }, completion: { [weak self] in self?.reloadPanels() })
    }

    @objc func makeHardLink(_ sender: Any?) {
        createLink(title: "Link", message: "Name des neuen Links:") { existing, link in try self.localSystem.makeHardLink(link, to: existing) }
    }

    @objc func makeSymbolicLink(_ sender: Any?) {
        createLink(title: "Symbolischer Link", message: "Name des neuen Links:") { existing, link in try self.localSystem.makeSymlink(link, target: existing) }
    }

    @objc func makeRelativeSymbolicLink(_ sender: Any?) {
        createLink(title: "Relativer symbolischer Link", message: "Name des neuen Links:") { existing, link in
            try self.localSystem.makeSymlink(link, target: PosixPath.relative(from: PosixPath.parent(link), to: existing))
        }
    }

    private func createLink(title: String, message: String, create: (String, String) throws -> Void) {
        let model = activePanel.model
        guard requireLocal(model, title), let entry = currentFile(model) else { return }
        let targetDirectory = inactivePanel.model.isLocal ? inactivePanel.model.path : model.path
        guard let text = Dialogs.prompt(title: title, message: message, value: PosixPath.join(targetDirectory, entry.name), confirm: "Anlegen") else { return }
        do {
            try create(model.fullPath(of: entry.name), PosixPath.resolve(text, relativeTo: model.path, home: NSHomeDirectory()))
        } catch {
            Dialogs.show(error: error)
        }
        reloadPanels()
    }

    @objc func editSymbolicLink(_ sender: Any?) {
        let model = activePanel.model
        guard requireLocal(model, "Symlink bearbeiten"), let entry = currentFile(model) else { return }
        guard entry.isSymlink else { return Dialogs.show(error: FileError("\(entry.name) ist kein symbolischer Link")) }
        let path = model.fullPath(of: entry.name)
        do {
            let current = try localSystem.readLink(path)
            guard let target = Dialogs.prompt(title: "Symbolischen Link bearbeiten", message: "Ziel von \(entry.name):", value: current, confirm: "Ändern") else { return }
            try localSystem.removeFile(path)
            try localSystem.makeSymlink(path, target: target)
        } catch {
            Dialogs.show(error: error)
        }
        reloadPanels()
    }

    @objc func viewFileByName(_ sender: Any?) {
        let model = activePanel.model
        guard let text = Dialogs.prompt(title: "Datei anzeigen", message: "Pfad der Datei:", value: model.path + "/", confirm: "Anzeigen") else { return }
        openEditor(system: model.fileSystem, path: PosixPath.resolve(text, relativeTo: model.path, home: model.fileSystem.homePath), readOnly: true)
    }

    @objc func compareDirectories(_ sender: Any?) {
        let first = panelViews[0].model
        let second = panelViews[1].model
        let left = first.markDifferences(against: second)
        let right = second.markDifferences(against: first)
        if left + right == 0 {
            Dialogs.info(title: "Verzeichnisse vergleichen", message: "Keine Unterschiede in Namen, Größe und Änderungszeit.")
        } else {
            Dialogs.info(title: "Verzeichnisse vergleichen", message: "Markiert: \(left) links, \(right) rechts.\nVerglichen werden Namen, Größe und Änderungszeit der sichtbaren Einträge.")
        }
    }

    private func selectedFilePair() -> (left: String, right: String)? {
        let active = activePanel.model
        let other = inactivePanel.model
        guard active.isLocal, other.isLocal else {
            Dialogs.show(error: FileError("Dateien lassen sich nur im lokalen Dateisystem vergleichen"))
            return nil
        }
        guard let mine = currentFile(active), !mine.isDirectory else {
            Dialogs.show(error: FileError("Setze den Cursor im aktiven Panel auf eine Datei. Im anderen Panel wird die Datei unter dem Cursor oder die gleichnamige verwendet."))
            return nil
        }
        let counterpart = currentFile(other).flatMap { $0.isDirectory ? nil : $0 } ?? other.rows.first { $0.name == mine.name && !$0.isDirectory }
        guard let counterpart else {
            Dialogs.show(error: FileError("Im anderen Panel gibt es keine passende Datei. Setze dort den Cursor auf eine Datei oder verwende denselben Dateinamen."))
            return nil
        }
        let mineIsLeft = activePanel === panelViews[0]
        let minePath = active.fullPath(of: mine.name)
        let otherPath = other.fullPath(of: counterpart.name)
        return mineIsLeft ? (minePath, otherPath) : (otherPath, minePath)
    }

    @objc func compareFiles(_ sender: Any?) {
        guard let pair = selectedFilePair() else { return }
        let outputPath = NSTemporaryDirectory() + "moonlight-diff/" + PosixPath.name(pair.left) + " ↔ " + PosixPath.name(pair.right) + ".diff"
        let status = Box<Int32>()
        runner.run(title: "Vergleiche …", { _ in
            try FileManager.default.createDirectory(atPath: PosixPath.parent(outputPath), withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
            process.arguments = ["-u", pair.left, pair.right]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus < 2 else { throw FileError(String(decoding: errorData, as: UTF8.self)) }
            try data.write(to: URL(fileURLWithPath: outputPath))
            status.value = process.terminationStatus
        }, completion: { [weak self] in
            guard let status = status.value else { return }
            if status == 0 {
                Dialogs.info(title: "Dateien vergleichen", message: "Die Dateien sind identisch.")
            } else {
                self?.openEditor(system: LocalFileSystem.shared, path: outputPath, readOnly: true)
            }
        })
    }

    @objc func compareFilesInFileMerge(_ sender: Any?) {
        guard let pair = selectedFilePair() else { return }
        let developer = (try? Process.output("/usr/bin/xcode-select", ["-p"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard FileManager.default.fileExists(atPath: developer + "/../Applications/FileMerge.app") else {
            return Dialogs.show(error: FileError("FileMerge wurde nicht gefunden. Es gehört zu Xcode; „Dateien vergleichen“ funktioniert auch ohne."))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/opendiff")
        process.arguments = [pair.left, pair.right]
        do {
            try process.run()
        } catch {
            Dialogs.show(error: error)
        }
    }

    @objc func showDirectorySizes(_ sender: Any?) {
        activePanel.model.calculateDirectorySizes()
    }

    @objc func findFiles(_ sender: Any?) {
        let model = activePanel.model
        guard let values = Dialogs.fields(title: "Datei suchen", message: "Start: \(model.path)\nInhaltssuche nur im lokalen Dateisystem, Groß-/Kleinschreibung wird beachtet.", fields: [("Name:", "*"), ("Inhalt:", "")], confirm: "Suchen") else { return }
        guard let window else { return }
        let finder = FindDialog(fileSystem: model.fileSystem, root: model.path, criteria: SearchCriteria(namePattern: values[0], content: values[1]))
        finder.onSelect = { path in model.navigate(to: PosixPath.parent(path), selecting: PosixPath.name(path)) }
        finder.onPanelize = { paths in model.navigate(to: "/", on: PanelizedFileSystem(base: model.fileSystem, paths: paths, title: "Suchergebnis")) }
        finder.onClose = { [weak self] in self?.activeFind = nil }
        activeFind = finder
        finder.present(on: window)
    }

    @objc func panelizeCommand(_ sender: Any?) {
        let model = activePanel.model
        guard requireLocal(model, "Externes Panelisieren"),
              let values = Dialogs.fields(title: "Externes Panelisieren", message: "Befehl, der Pfade ausgibt (eine Zeile pro Datei), in \(model.path):", fields: [("Befehl:", "find . -type f -mtime -1")], confirm: "Ausführen"),
              !values[0].isEmpty else { return }
        let command = values[0]
        let directory = model.path
        let found = Box<[String]>()
        runner.run(title: "Führe aus …", { _ in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            found.value = String(decoding: data, as: UTF8.self).split(separator: "\n").map { PosixPath.resolve(String($0), relativeTo: directory, home: NSHomeDirectory()) }.filter { LocalFileSystem.shared.exists($0) }
        }, completion: {
            guard let paths = found.value, !paths.isEmpty else { return Dialogs.show(error: FileError("Der Befehl hat keine vorhandenen Pfade geliefert")) }
            model.navigate(to: "/", on: PanelizedFileSystem(base: LocalFileSystem.shared, paths: paths, title: command))
        })
    }

    @objc func showCommandHistory(_ sender: Any?) {
        let entries = commandLine.entries.reversed().map { $0 }
        guard !entries.isEmpty else { return Dialogs.show(error: FileError("Die Befehlschronik ist leer")) }
        guard let result = Dialogs.form(title: "Befehlschronik", popup: ("Befehl:", entries, 0), confirm: "Übernehmen") else { return }
        commandLine.replace(with: entries[result.choice])
    }

    @objc func showViewedFiles(_ sender: Any?) {
        let files = Settings.viewedFiles.filter { localSystem.exists($0.path) }
        let menu = NSMenu()
        for (index, file) in files.enumerated() {
            let item = ClosureMenuItem("\(file.edited ? "F4" : "F3")  \(file.path)") { [unowned self] in
                openEditor(system: localSystem, path: file.path, readOnly: !file.edited)
            }
            if index < 9 {
                item.keyEquivalent = String(index + 1)
                item.keyEquivalentModifierMask = []
            }
            menu.addItem(item)
        }
        if files.isEmpty {
            menu.addItem(NSMenuItem(title: "Noch keine Dateien angesehen", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Chronik leeren") { Settings.viewedFiles = [] })
        }
        popUp(menu, title: "Angesehene Dateien")
    }

    @objc func showHotlist(_ sender: Any?) {
        let menu = NSMenu()
        let model = activePanel.model
        let list = Settings.hotlist
        for (index, path) in list.enumerated() {
            let item = ClosureMenuItem(path) { [unowned self] in activePanel.model.navigate(to: path, on: localSystem) }
            if index < 9 {
                item.keyEquivalent = String(index + 1)
                item.keyEquivalentModifierMask = []
            }
            menu.addItem(item)
        }
        if !list.isEmpty { menu.addItem(.separator()) }
        if model.isLocal, !list.contains(model.path) {
            menu.addItem(ClosureMenuItem("Aktuellen Ordner hinzufügen") { Settings.hotlist = list + [model.path] })
        }
        for path in list { menu.addItem(ClosureMenuItem("Entfernen: \(path)") { Settings.hotlist = list.filter { $0 != path } }) }
        popUp(menu, title: "Verzeichnis-Hotlist")
    }

    @objc func showBackgroundJobs(_ sender: Any?) {
        let menu = NSMenu()
        for job in runner.backgroundJobs {
            menu.addItem(ClosureMenuItem("Abbrechen: \(job.title)" + (job.percent.map { " (\($0) %)" } ?? "")) { job.operation.cancel() })
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "Keine Hintergrundaufgaben", action: nil, keyEquivalent: "")) }
        popUp(menu, title: "Hintergrundaufgaben")
    }

    @objc func showConnections(_ sender: Any?) {
        let menu = NSMenu()
        for (side, panel) in zip(["Links", "Rechts"], panelViews) where !panel.model.isLocal {
            menu.addItem(ClosureMenuItem("\(side): \(panel.model.fileSystem.displayName) schließen") { panel.model.navigate(to: NSHomeDirectory(), on: LocalFileSystem.shared) })
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "Keine aktiven Verbindungen", action: nil, keyEquivalent: "")) }
        popUp(menu, title: "Aktive Verbindungen")
    }

    @objc func showSavedPasswords(_ sender: Any?) {
        let menu = NSMenu()
        for account in Keychain.accounts() {
            menu.addItem(ClosureMenuItem("Passwort vergessen: \(account)") { Keychain.delete(account: account) })
        }
        if menu.items.isEmpty { menu.addItem(NSMenuItem(title: "Keine gespeicherten Passwörter", action: nil, keyEquivalent: "")) }
        popUp(menu, title: "Gespeicherte Passwörter")
    }

    @objc func userMenu(_ sender: Any?) {
        let model = activePanel.model
        guard requireLocal(model, "Das Benutzermenü") else { return }
        let other = inactivePanel.model
        let context = UserMenuContext(
            currentName: model.currentEntry?.name ?? "",
            directory: model.path,
            selection: model.selectedNames,
            otherDirectory: other.path,
            otherName: other.currentEntry?.name ?? ""
        )
        let menu = NSMenu()
        for entry in UserMenu.load() {
            let item = ClosureMenuItem(entry.title) { [unowned self] in runInTerminal(UserMenu.expand(entry.script, context: context)) }
            item.keyEquivalent = entry.key
            item.keyEquivalentModifierMask = []
            menu.addItem(item)
        }
        popUp(menu, title: "Benutzermenü")
    }

    @objc func editFileActions(_ sender: Any?) {
        let url = FileActions.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileActions.defaultText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return Dialogs.show(error: error)
            }
        }
        openEditor(system: LocalFileSystem.shared, path: url.path, readOnly: false)
    }

    @objc func editUserMenu(_ sender: Any?) {
        let url = UserMenu.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try UserMenu.defaultText.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                return Dialogs.show(error: error)
            }
        }
        openEditor(system: LocalFileSystem.shared, path: url.path, readOnly: false)
    }

    func popUp(_ menu: NSMenu, title: String? = nil) {
        ClassicPopup.show(menu, title: title, in: window)
    }

    @objc func chooseListFormat(_ sender: Any?) {
        let model = activePanel.model
        let formats = ListFormat.allCases
        guard let result = Dialogs.form(title: "Listenformat", popup: ("Anzeige:", formats.map(\.title), formats.firstIndex(of: model.format) ?? 0)) else { return }
        model.setFormat(formats[result.choice])
    }

    @objc func chooseSortOrder(_ sender: Any?) {
        let model = activePanel.model
        let keys: [(String, SortKey)] = [("Name", .name), ("Endung", .fileExtension), ("Größe", .size), ("Datum", .date)]
        guard let result = Dialogs.form(
            title: "Sortierreihenfolge",
            popup: ("Sortieren nach:", keys.map(\.0), keys.firstIndex { $0.1 == model.sortKey } ?? 0),
            checks: [("Umgekehrt", !model.ascending), ("Verzeichnisse zuerst", model.dirsFirst), ("Groß-/Kleinschreibung beachten", model.caseSensitive)]
        ) else { return }
        model.applySortOptions(key: keys[result.choice].1, ascending: !result.checks[0], dirsFirst: result.checks[1], caseSensitive: result.checks[2])
    }

    @objc func chooseFilter(_ sender: Any?) {
        let model = activePanel.model
        guard let values = Dialogs.fields(title: "Filter", message: "Muster für Dateien, durch Leerzeichen getrennt (z. B. *.swift *.md). Leer zeigt alles.", fields: [("Muster:", model.filter)], confirm: "Anwenden") else { return }
        model.setFilter(values[0])
    }

    @objc func showConfiguration(_ sender: Any?) {
        let hidden = activePanel.model.showHidden
        let checksForUpdates = Settings.updateCheck == .enabled
        guard let result = Dialogs.form(title: "Konfiguration", checks: [("Versteckte Dateien anzeigen", hidden), ("Lokal in den Papierkorb statt endgültig löschen", Settings.useTrash), ("Beim Start nach Updates suchen", checksForUpdates)]) else { return }
        if result.checks[0] != hidden { panelViews.forEach { $0.model.toggleHidden() } }
        Settings.useTrash = result.checks[1]
        if result.checks[2] != checksForUpdates { Settings.updateCheck = result.checks[2] ? .enabled : .disabled }
    }

    @objc func showLayout(_ sender: Any?) {
        guard let result = Dialogs.form(title: "Layout", checks: [
            ("Panels untereinander statt nebeneinander", Settings.verticalLayout),
            ("Menüzeile anzeigen", Settings.showMenuLine),
            ("Kommandozeile anzeigen", Settings.showCommandLine),
            ("Tipps anzeigen", Settings.showHints),
            ("Funktionsleiste anzeigen", Settings.showKeyBar),
        ]) else { return }
        Settings.verticalLayout = result.checks[0]
        Settings.showMenuLine = result.checks[1]
        Settings.showCommandLine = result.checks[2]
        Settings.showHints = result.checks[3]
        Settings.showKeyBar = result.checks[4]
        applyLayout()
    }

    @objc func arrangePanels(_ sender: Any?) {
        Settings.verticalLayout.toggle()
        applyLayout()
    }

    @objc func showPanelOptions(_ sender: Any?) {
        let model = activePanel.model
        guard let result = Dialogs.form(title: "Paneloptionen", message: "Gilt für beide Panels.", checks: [("Verzeichnisse zuerst", model.dirsFirst), ("Groß-/Kleinschreibung beim Sortieren beachten", model.caseSensitive)]) else { return }
        for panel in panelViews {
            panel.model.applySortOptions(key: panel.model.sortKey, ascending: panel.model.ascending, dirsFirst: result.checks[0], caseSensitive: result.checks[1])
        }
    }

    @objc func showConfirmations(_ sender: Any?) {
        guard let result = Dialogs.form(title: "Nachfragen", checks: [("Löschen bestätigen", Settings.confirmDelete), ("Überschreiben bestätigen", Settings.confirmOverwrite), ("Beenden bestätigen", Settings.confirmExit)]) else { return }
        Settings.confirmDelete = result.checks[0]
        Settings.confirmOverwrite = result.checks[1]
        Settings.confirmExit = result.checks[2]
    }

    @objc func showAppearance(_ sender: Any?) {
        guard let result = Dialogs.form(title: "Aussehen", popup: ("Farbschema:", Palette.all.map(\.name), Settings.scheme)) else { return }
        Theme.select(result.choice)
    }

    @objc func saveSettings(_ sender: Any?) {
        saveState()
    }
}
