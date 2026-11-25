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
        let modes: [(String, PanelMode)] = [(localized("Dateiliste"), .list), (localized("Schnellansicht"), .quickView), (localized("Info"), .info), (localized("Baum"), .tree)]
        for (title, mode) in modes {
            menu.addItem(ClosureMenuItem(title, checked: panel.mode == mode) { [unowned self] in
                focus(mode == .quickView || mode == .info ? panelViews[1 - side] : panel)
                panel.setMode(mode)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(localized("Listenformat …")) { [unowned self] in focus(panel); chooseListFormat(nil) })
        menu.addItem(ClosureMenuItem(localized("Sortierreihenfolge …")) { [unowned self] in focus(panel); chooseSortOrder(nil) })
        menu.addItem(ClosureMenuItem(localized("Filter …"), checked: !model.filter.isEmpty) { [unowned self] in focus(panel); chooseFilter(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(localized("Netzwerkverbindung …")) { [unowned self] in focus(panel); connect(nil) })
        menu.addItem(ClosureMenuItem(localized("Gehe zu Pfad …")) { [unowned self] in focus(panel); goToPath(nil) })
        menu.addItem(ClosureMenuItem(localized("Home-Ordner")) { [unowned self] in focus(panel); goHome(nil) })
        let back = localized("Zurück   ⌘←")
        let forward = localized("Vorwärts   ⌘→")
        menu.addItem(model.canGoBack ? ClosureMenuItem(back) { [unowned self] in focus(panel); model.goBack() } : NSMenuItem(title: back, action: nil, keyEquivalent: ""))
        menu.addItem(model.canGoForward ? ClosureMenuItem(forward) { [unowned self] in focus(panel); model.goForward() } : NSMenuItem(title: forward, action: nil, keyEquivalent: ""))
        menu.addItem(ClosureMenuItem(localized("Verlauf …")) { [unowned self] in focus(panel); showHistory(of: panel) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(localized("Anordnen")) { [unowned self] in arrangePanels(nil) })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(localized("Neu einlesen   ⌘R")) { model.reload() })
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            (localized("Ansicht   F3"), viewFile), (localized("Quick Look   ⌘Y"), quickLookFile), (localized("Datei anzeigen …"), viewFileByName), (localized("Bearbeiten   F4"), editFile), (localized("Neue Datei …   ⇧F4"), newFile), (localized("Kopieren   F5"), copyFiles), (localized("In Archiv packen …   ⇧F5"), packIntoArchive), nil,
            (localized("Chmod …"), changePermissions), (localized("Link …"), makeHardLink), (localized("Symbolischer Link …"), makeSymbolicLink), (localized("Relativer symbolischer Link …"), makeRelativeSymbolicLink),
            (localized("Symbolischen Link bearbeiten …"), editSymbolicLink), (localized("Chown …"), changeOwner), nil,
            (localized("Umbenennen/Verschieben   F6"), moveFiles), (localized("Umbenennen   ⇧F6"), renameFile), (localized("Neues Verzeichnis erstellen   F7"), makeDirectory),
            (localized("Löschen   F8"), deleteFiles), (localized("Endgültig löschen   ⇧F8"), deleteFilesPermanently), (localized("Schnelles cd …"), goToPath), nil,
        ], to: menu)
        add([
            (localized("Gruppe auswählen …   +"), { _ in self.markPattern(select: true) }), (localized("Gruppe abwählen …   −"), { _ in self.markPattern(select: false) }),
            (localized("Auswahl umkehren   *"), { _ in self.activePanel.model.invertMarks() }), (localized("Alle auswählen"), { _ in self.activePanel.model.markAll() }), nil,
            (localized("Verlassen   F10"), { _ in NSApp.terminate(nil) }),
        ], to: menu)
        return menu
    }

    private func commandMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            (localized("Benutzermenü   F2"), userMenu), (localized("Terminal ein/aus   Ctrl-O"), toggleTerminal), (localized("Verzeichnisbaum"), { _ in self.activePanel.setMode(.tree) }), (localized("Datei suchen …"), findFiles), (localized("Externes Panelisieren …"), panelizeCommand), (localized("Panels vertauschen   ⌘U"), swapPanels),
            (localized("Verzeichnisse vergleichen"), compareDirectories), (localized("Dateien vergleichen"), compareFiles), (localized("Dateien in FileMerge vergleichen"), compareFilesInFileMerge), (localized("Verzeichnisgrößen anzeigen"), showDirectorySizes), nil,
            (localized("Befehlschronik …"), showCommandHistory), (localized("Chronik angesehener Dateien …"), showViewedFiles), (localized("Verzeichnis-Hotlist …   ⌘D"), showHotlist), (localized("Aktive Verbindungen …"), showConnections), (localized("Freigeben …"), shareFolders), (localized("Hintergrundaufgaben …"), showBackgroundJobs), (localized("Gespeicherte Passwörter …"), showSavedPasswords), nil,
            (localized("Benutzermenü bearbeiten"), editUserMenu), (localized("Dateizuordnung bearbeiten"), editFileActions),
        ], to: menu)
        return menu
    }

    private func optionsMenu() -> NSMenu {
        let menu = NSMenu()
        add([
            (localized("Konfiguration …"), showConfiguration), (localized("Layout …"), showLayout), (localized("Paneloptionen …"), showPanelOptions), (localized("Nachfragen …"), showConfirmations), (localized("Aussehen …"), showAppearance), nil,
            (localized("Einstellungen speichern"), saveSettings),
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
