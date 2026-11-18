import AppKit

enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        for submenu in [appMenu(), fileMenu(), editMenu(), viewMenu(), windowMenu()] {
            let item = NSMenuItem()
            item.submenu = submenu
            menu.addItem(item)
        }
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Moonlight Commander")
        menu.addItem(item("Über Moonlight Commander", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Moonlight Commander ausblenden", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Moonlight Commander beenden", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "Datei")
        menu.addItem(item("SFTP verbinden …", #selector(MainWindowController.connect(_:)), "k"))
        menu.addItem(item("Gehe zu Pfad …", #selector(MainWindowController.goToPath(_:)), "l"))
        menu.addItem(item("Home-Ordner", #selector(MainWindowController.goHome(_:)), "h", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Quick Look", #selector(MainWindowController.quickLookFile(_:)), "y"))
        menu.addItem(item("Anzeigen (F3)", #selector(MainWindowController.viewFile(_:)), "3", .option))
        menu.addItem(item("Bearbeiten (F4)", #selector(MainWindowController.editFile(_:)), "4", .option))
        menu.addItem(item("Neue Datei …", #selector(MainWindowController.newFile(_:)), "n"))
        menu.addItem(item("Kopieren (F5)", #selector(MainWindowController.copyFiles(_:)), "5", .option))
        menu.addItem(item("Verschieben (F6)", #selector(MainWindowController.moveFiles(_:)), "6", .option))
        menu.addItem(item("Umbenennen (⇧F6)", #selector(MainWindowController.renameFile(_:)), "6", [.option, .shift]))
        menu.addItem(item("Neuer Ordner (F7)", #selector(MainWindowController.makeDirectory(_:)), "7", .option))
        menu.addItem(item("Löschen (F8)", #selector(MainWindowController.deleteFiles(_:)), "8", .option))
        menu.addItem(item("Endgültig löschen (⇧F8)", #selector(MainWindowController.deleteFilesPermanently(_:)), "8", [.option, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Sichern", #selector(EditorWindowController.saveDocument(_:)), "s"))
        menu.addItem(item("Fenster schließen", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Bearbeiten")
        menu.addItem(item("Rückgängig", Selector(("undo:")), "z"))
        menu.addItem(item("Wiederholen", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Ausschneiden", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Kopieren", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Einsetzen", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Alles auswählen", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Suchen …", #selector(EditorWindowController.findText(_:)), "f"))
        menu.addItem(item("Weitersuchen", #selector(EditorWindowController.findNext(_:)), "g"))
        menu.addItem(item("Ersetzen …", #selector(EditorWindowController.replaceText(_:)), "f", [.command, .option]))
        menu.addItem(item("Gehe zu Zeile …", #selector(EditorWindowController.goToLine(_:)), "l", [.command, .option]))
        menu.addItem(item("Datei einfügen …", #selector(EditorWindowController.insertFile(_:)), "i", [.command, .option]))
        menu.addItem(item("Block sichern …", #selector(EditorWindowController.saveBlock(_:)), "b", [.command, .option]))
        menu.addItem(item("Codierung …", #selector(EditorWindowController.chooseEncoding(_:)), "e", [.command, .option]))
        menu.addItem(item("Hex-Ansicht", #selector(EditorWindowController.toggleHex(_:)), "h", [.command, .option]))
        menu.addItem(item("Zeilenumbruch", #selector(EditorWindowController.toggleWrap(_:)), "w", [.command, .option]))
        menu.addItem(item("Zeile löschen", #selector(EditorWindowController.deleteLine(_:)), "k", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Ansicht")
        menu.addItem(item("Nach Name sortieren", #selector(MainWindowController.sortByName(_:)), "1"))
        menu.addItem(item("Nach Endung sortieren", #selector(MainWindowController.sortByExtension(_:)), "2"))
        menu.addItem(item("Nach Größe sortieren", #selector(MainWindowController.sortBySize(_:)), "3"))
        menu.addItem(item("Nach Datum sortieren", #selector(MainWindowController.sortByDate(_:)), "4"))
        menu.addItem(.separator())
        menu.addItem(item("Versteckte Dateien", #selector(MainWindowController.toggleHidden(_:)), ".", [.command, .shift]))
        menu.addItem(item("Aktualisieren (F9)", #selector(MainWindowController.refresh(_:)), "r"))
        menu.addItem(item("Terminal ein/aus", #selector(MainWindowController.toggleTerminal(_:)), "o", .control))
        menu.addItem(item("Panels tauschen", #selector(MainWindowController.swapPanels(_:)), "u"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Fenster")
        menu.addItem(item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoomen", #selector(NSWindow.performZoom(_:))))
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}
