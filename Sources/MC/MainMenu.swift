import AppKit
import MCCore

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
        let about = item(localized("Über Moonlight Commander"), #selector(AboutPanel.show))
        about.target = AboutPanel.shared
        menu.addItem(about)
        let updates = item(localized("Nach Updates suchen …"), #selector(UpdateNotifier.checkNow))
        updates.target = UpdateNotifier.shared
        menu.addItem(updates)
        let imprint = item(localized("Impressum …"), #selector(AboutPanel.openImprint))
        imprint.target = AboutPanel.shared
        menu.addItem(imprint)
        menu.addItem(.separator())
        menu.addItem(item(localized("Moonlight Commander ausblenden"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(localized("Andere ausblenden"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item(localized("Moonlight Commander beenden"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: localized("Datei"))
        menu.addItem(item(localized("Verbinden (SFTP/FTP) …"), #selector(MainWindowController.connect(_:)), "k"))
        menu.addItem(item(localized("Gehe zu Pfad …"), #selector(MainWindowController.goToPath(_:)), "l"))
        menu.addItem(item(localized("Home-Ordner"), #selector(MainWindowController.goHome(_:)), "h", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(localized("Quick Look"), #selector(MainWindowController.quickLookFile(_:)), "y"))
        menu.addItem(item(localized("Anzeigen (F3)"), #selector(MainWindowController.viewFile(_:)), "3", .option))
        menu.addItem(item(localized("Bearbeiten (F4)"), #selector(MainWindowController.editFile(_:)), "4", .option))
        menu.addItem(item(localized("Neue Datei …"), #selector(MainWindowController.newFile(_:)), "n"))
        menu.addItem(item(localized("Kopieren (F5)"), #selector(MainWindowController.copyFiles(_:)), "5", .option))
        menu.addItem(item(localized("Verschieben (F6)"), #selector(MainWindowController.moveFiles(_:)), "6", .option))
        menu.addItem(item(localized("Umbenennen (⇧F6)"), #selector(MainWindowController.renameFile(_:)), "6", [.option, .shift]))
        menu.addItem(item(localized("Neuer Ordner (F7)"), #selector(MainWindowController.makeDirectory(_:)), "7", .option))
        menu.addItem(item(localized("Löschen (F8)"), #selector(MainWindowController.deleteFiles(_:)), "8", .option))
        menu.addItem(item(localized("Endgültig löschen (⇧F8)"), #selector(MainWindowController.deleteFilesPermanently(_:)), "8", [.option, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(localized("Sichern"), #selector(EditorWindowController.saveDocument(_:)), "s"))
        menu.addItem(item(localized("Fenster schließen"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: localized("Bearbeiten"))
        menu.addItem(item(localized("Rückgängig"), Selector(("undo:")), "z"))
        menu.addItem(item(localized("Wiederholen"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(localized("Ausschneiden"), #selector(NSText.cut(_:)), "x"))
        menu.addItem(item(localized("Kopieren"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(localized("Einsetzen"), #selector(NSText.paste(_:)), "v"))
        menu.addItem(item(localized("Alles auswählen"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item(localized("Suchen …"), #selector(EditorWindowController.findText(_:)), "f"))
        menu.addItem(item(localized("Weitersuchen"), #selector(EditorWindowController.findNext(_:)), "g"))
        menu.addItem(item(localized("Ersetzen …"), #selector(EditorWindowController.replaceText(_:)), "f", [.command, .option]))
        menu.addItem(item(localized("Gehe zu Zeile …"), #selector(EditorWindowController.goToLine(_:)), "l", [.command, .option]))
        menu.addItem(item(localized("Datei einfügen …"), #selector(EditorWindowController.insertFile(_:)), "i", [.command, .option]))
        menu.addItem(item(localized("Block sichern …"), #selector(EditorWindowController.saveBlock(_:)), "b", [.command, .option]))
        menu.addItem(item(localized("Codierung …"), #selector(EditorWindowController.chooseEncoding(_:)), "e", [.command, .option]))
        menu.addItem(item(localized("Hex-Ansicht"), #selector(EditorWindowController.toggleHex(_:)), "h", [.command, .option]))
        menu.addItem(item(localized("Vorschau/Quelltext"), #selector(EditorWindowController.togglePreview(_:)), "p", [.command, .option]))
        menu.addItem(item(localized("Zeilenumbruch"), #selector(EditorWindowController.toggleWrap(_:)), "w", [.command, .option]))
        menu.addItem(item(localized("Zeile löschen"), #selector(EditorWindowController.deleteLine(_:)), "k", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: localized("Ansicht"))
        menu.addItem(item(localized("Nach Name sortieren"), #selector(MainWindowController.sortByName(_:)), "1"))
        menu.addItem(item(localized("Nach Endung sortieren"), #selector(MainWindowController.sortByExtension(_:)), "2"))
        menu.addItem(item(localized("Nach Größe sortieren"), #selector(MainWindowController.sortBySize(_:)), "3"))
        menu.addItem(item(localized("Nach Datum sortieren"), #selector(MainWindowController.sortByDate(_:)), "4"))
        menu.addItem(.separator())
        menu.addItem(item(localized("Versteckte Dateien"), #selector(MainWindowController.toggleHidden(_:)), ".", [.command, .shift]))
        menu.addItem(item(localized("Aktualisieren (F9)"), #selector(MainWindowController.refresh(_:)), "r"))
        menu.addItem(item(localized("Terminal ein/aus"), #selector(MainWindowController.toggleTerminal(_:)), "o", .control))
        menu.addItem(item(localized("Verzeichnis-Hotlist"), #selector(MainWindowController.showHotlist(_:)), "d"))
        menu.addItem(item(localized("Panels tauschen"), #selector(MainWindowController.swapPanels(_:)), "u"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: localized("Fenster"))
        menu.addItem(item(localized("Im Dock ablegen"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(localized("Zoomen"), #selector(NSWindow.performZoom(_:))))
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }
}
