import AppKit
import MCCore

extension MainWindowController {
    func menu(at index: Int) -> NSMenu {
        switch index {
        case 0: return panelMenu(for: 0)
        case 1: return fileMenu()
        case 2: return commandMenu()
        case 3: return optionsMenu()
        default: return panelMenu(for: 1)
        }
    }

    private func panelMenu(for side: Int) -> NSMenu {
        let panel = panelViews[side]
        let model = panel.model
        let menu = NSMenu()
        let modes: [(String, PanelMode)] = [("Dateiliste", .list), ("Schnellansicht", .quickView), ("Info", .info), ("Baum", .tree)]
        for (title, mode) in modes {
            menu.addItem(ClosureMenuItem(title, checked: panel.mode == mode) { [unowned self] in
                focus(mode == .quickView || mode == .info ? panelViews[1 - side] : panel)
                panel.setMode(mode)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Listenformat …") { [unowned self] in focus(panel); chooseListFormat(nil) })
        menu.addItem(ClosureMenuItem("Sortierreihenfolge …") { [unowned self] in focus(panel); chooseSortOrder(nil) })
        menu.addItem(ClosureMenuItem("Filter …", checked: !model.filter.isEmpty) { [unowned self] in focus(panel); chooseFilter(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("SFTP-/FTP-Verbindung …") { [unowned self] in focus(panel); connect(nil) })
        menu.addItem(ClosureMenuItem("Gehe zu Pfad …") { [unowned self] in focus(panel); goToPath(nil) })
        menu.addItem(ClosureMenuItem("Home-Ordner") { [unowned self] in focus(panel); goHome(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Anordnen") { [unowned self] in arrangePanels(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Neu einlesen   ⌘R") { model.reload() })
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            ("Ansicht   F3", viewFile), ("Quick Look   ⌘Y", quickLookFile), ("Datei anzeigen …", viewFileByName), ("Bearbeiten   F4", editFile), ("Neue Datei …   ⇧F4", newFile), ("Kopieren   F5", copyFiles), nil,
            ("Chmod …", changePermissions), ("Link …", makeHardLink), ("Symbolischer Link …", makeSymbolicLink), ("Relativer symbolischer Link …", makeRelativeSymbolicLink),
            ("Symbolischen Link bearbeiten …", editSymbolicLink), ("Chown …", changeOwner), nil,
            ("Umbenennen/Verschieben   F6", moveFiles), ("Umbenennen   ⇧F6", renameFile), ("Neues Verzeichnis erstellen   F7", makeDirectory),
            ("Löschen   F8", deleteFiles), ("Endgültig löschen   ⇧F8", deleteFilesPermanently), ("Schnelles cd …", goToPath), nil,
        ], to: menu)
        add([
            ("Gruppe auswählen …   +", { _ in self.markPattern(select: true) }), ("Gruppe abwählen …   −", { _ in self.markPattern(select: false) }),
            ("Auswahl umkehren   *", { _ in self.activePanel.model.invertMarks() }), ("Alle auswählen", { _ in self.activePanel.model.markAll() }), nil,
            ("Verlassen   F10", { _ in NSApp.terminate(nil) }),
        ], to: menu)
        return menu
    }

    private func commandMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            ("Benutzermenü   F2", userMenu), ("Terminal ein/aus   Ctrl-O", toggleTerminal), ("Verzeichnisbaum", { _ in self.activePanel.setMode(.tree) }), ("Datei suchen …", findFiles), ("Externes Panelisieren …", panelizeCommand), ("Panels vertauschen   ⌘U", swapPanels),
            ("Verzeichnisse vergleichen", compareDirectories), ("Dateien vergleichen", compareFiles), ("Dateien in FileMerge vergleichen", compareFilesInFileMerge), ("Verzeichnisgrößen anzeigen", showDirectorySizes), nil,
            ("Befehlschronik …", showCommandHistory), ("Chronik angesehener Dateien …", showViewedFiles), ("Verzeichnis-Hotlist …   ⌘D", showHotlist), ("Aktive Verbindungen …", showConnections), ("Hintergrundaufgaben …", showBackgroundJobs), ("Gespeicherte Passwörter …", showSavedPasswords), nil,
            ("Benutzermenü bearbeiten", editUserMenu), ("Dateizuordnung bearbeiten", editFileActions),
        ], to: menu)
        return menu
    }

    private func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            ("Konfiguration …", showConfiguration), ("Layout …", showLayout), ("Paneloptionen …", showPanelOptions), ("Nachfragen …", showConfirmations), ("Aussehen …", showAppearance), nil,
            ("Einstellungen speichern", saveSettings),
        ], to: menu)
        return menu
    }

    private func add(_ items: [(String, (Any?) -> Void)?], to menu: NSMenu) {
        for item in items {
            if let (title, action) = item {
                menu.addItem(ClosureMenuItem(title) { [unowned self] in
                    focus(activePanel)
                    action(nil)
                })
            } else {
                menu.addItem(.separator())
            }
        }
    }

    private func focus(_ panel: PanelView) {
        activate(panel)
        window?.makeFirstResponder(panel)
    }
}
