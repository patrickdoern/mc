import AppKit
import MCCore

enum Dialogs {
    static func prompt(title: String, message: String, value: String = "", confirm: String = "OK", history: [String] = []) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Abbrechen")
        let field: NSTextField = history.isEmpty ? NSTextField(string: value) : comboBox(history: history, value: value)
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let result = field.stringValue.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    struct FormResult {
        let choice: Int
        let checks: [Bool]
    }

    static func form(title: String, message: String = "", popup: (label: String, options: [String], selected: Int)? = nil, checks: [(title: String, value: Bool)] = [], confirm: String = "OK") -> FormResult? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Abbrechen")
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        var button: NSPopUpButton?
        if let popup {
            let chooser = NSPopUpButton(frame: .zero, pullsDown: false)
            chooser.addItems(withTitles: popup.options)
            chooser.selectItem(at: popup.selected)
            button = chooser
            let row = NSStackView(views: [NSTextField(labelWithString: popup.label), chooser])
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        let boxes = checks.map { check -> NSButton in
            let box = NSButton(checkboxWithTitle: check.title, target: nil, action: nil)
            box.state = check.value ? .on : .off
            stack.addArrangedSubview(box)
            return box
        }
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return FormResult(choice: button?.indexOfSelectedItem ?? 0, checks: boxes.map { $0.state == .on })
    }

    static func fields(title: String, message: String = "", fields: [(label: String, value: String)], confirm: String = "OK") -> [String]? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Abbrechen")
        let inputs = fields.map { NSTextField(string: $0.value) }
        let rows = zip(fields, inputs).map { field, input -> NSStackView in
            let label = NSTextField(labelWithString: field.label)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            input.widthAnchor.constraint(equalToConstant: 320).isActive = true
            let row = NSStackView(views: [label, input])
            row.spacing = 8
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = inputs.first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map { $0.stringValue.trimmingCharacters(in: .whitespaces) }
    }

    static func secret(_ message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Abbrechen")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func confirm(title: String, message: String, confirm: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        let button = alert.addButton(withTitle: confirm)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func show(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Fehler"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    static func conflict(_ info: ConflictInfo) -> ConflictChoice {
        let alert = NSAlert()
        alert.messageText = "Datei existiert bereits"
        alert.informativeText = "\(info.path)\n\nNeu:  \(describe(info.source))\nAlt:   \(describe(info.existing))"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Überschreiben")
        alert.addButton(withTitle: "Alle überschreiben")
        alert.addButton(withTitle: "Überspringen")
        alert.addButton(withTitle: "Alle überspringen")
        alert.addButton(withTitle: "Abbrechen")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .overwriteAll
        case .alertThirdButtonReturn: return .skip
        case NSApplication.ModalResponse(rawValue: 1003): return .skipAll
        default: return .cancel
        }
    }

    static func failure(path: String, error: Error) -> FailureChoice {
        let alert = NSAlert()
        alert.messageText = "Fehler bei \(PosixPath.name(path))"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Überspringen")
        alert.addButton(withTitle: "Alle überspringen")
        alert.addButton(withTitle: "Abbrechen")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .skip
        case .alertSecondButtonReturn: return .skipAll
        default: return .abort
        }
    }

    static func askToSave(name: String) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "„\(name)“ wurde geändert."
        alert.informativeText = "Änderungen speichern?"
        alert.addButton(withTitle: "Speichern")
        alert.addButton(withTitle: "Nicht speichern")
        alert.addButton(withTitle: "Abbrechen")
        return alert.runModal()
    }

    private static func describe(_ entry: FileEntry) -> String {
        "\(Formatting.exactSize(entry.size)), \(Formatting.date(entry.modified))"
    }

    private static func comboBox(history: [String], value: String) -> NSComboBox {
        let box = NSComboBox(frame: .zero)
        box.addItems(withObjectValues: history)
        box.stringValue = value
        box.completes = true
        return box
    }
}

final class DialogInteraction: SSHInteraction {
    func trustUnknownHost(_ host: String, keyType: String, fingerprint: String) -> Bool {
        onMain {
            Dialogs.confirm(
                title: "Unbekannter Host \(host)",
                message: "Der \(keyType)-Schlüssel dieses Servers ist noch nicht bekannt.\n\(fingerprint)\n\nVerbindung herstellen und Schlüssel in known_hosts speichern?",
                confirm: "Vertrauen"
            )
        }
    }

    func requestSecret(_ prompt: String) -> String? {
        onMain { Dialogs.secret(prompt) }
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
