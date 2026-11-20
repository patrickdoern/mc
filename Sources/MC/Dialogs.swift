import AppKit
import MCCore

enum Dialogs {
    static func prompt(title: String, message: String, value: String = "", confirm: String = "OK", history: [String] = []) -> String? {
        let dialog = ClassicDialog(title: title, message: message)
        let field = dialog.addText(value: value)
        if !history.isEmpty { dialog.addChoice(label: "Verlauf", options: history, selected: 0) { field.stringValue = $0 } }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        guard dialog.run() == 0 else { return nil }
        let result = field.stringValue.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    struct FormResult {
        let choice: Int
        let checks: [Bool]
    }

    static func form(title: String, message: String = "", popup: (label: String, options: [String], selected: Int)? = nil, checks: [(title: String, value: Bool)] = [], confirm: String = "OK") -> FormResult? {
        let dialog = ClassicDialog(title: title, message: message)
        let choiceItem = popup.map { dialog.addChoice(label: $0.label, options: $0.options, selected: $0.selected) }
        let checkItems = checks.map { dialog.addCheck($0.title, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return FormResult(choice: choiceItem.map(dialog.choice) ?? 0, checks: checkItems.map(dialog.isChecked))
    }

    static func fields(title: String, message: String = "", fields: [(label: String, value: String)], confirm: String = "OK") -> [String]? {
        let dialog = ClassicDialog(title: title, message: message)
        let inputs = fields.map { dialog.addText(label: $0.label, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return inputs.map { $0.stringValue.trimmingCharacters(in: .whitespaces) }
    }

    static func searchForm(title: String, fields: [(label: String, value: String)], checks: [(title: String, value: Bool)], confirm: String) -> (values: [String], checks: [Bool])? {
        let dialog = ClassicDialog(title: title)
        let inputs = fields.map { dialog.addText(label: $0.label, value: $0.value) }
        let checkItems = checks.map { dialog.addCheck($0.title, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return (inputs.map(\.stringValue), checkItems.map(dialog.isChecked))
    }

    static func secret(_ message: String) -> String? {
        let dialog = ClassicDialog(title: "Eingabe", message: message)
        let field = dialog.addText(secure: true)
        dialog.addButton("OK", isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        return dialog.run() == 0 ? field.stringValue : nil
    }

    static func password(_ message: String) -> PasswordEntry? {
        let dialog = ClassicDialog(title: "Passwort", message: message)
        let field = dialog.addText(secure: true)
        let remember = dialog.addCheck("Im Schlüsselbund sichern", value: false)
        dialog.addButton("OK", isDefault: true)
        dialog.addButton("Abbrechen", isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return PasswordEntry(password: field.stringValue, remember: dialog.isChecked(remember))
    }

    static func confirm(title: String, message: String, confirm: String, cancel: String = "Abbrechen", destructive: Bool = false) -> Bool {
        let dialog = ClassicDialog(title: title, message: message, warning: destructive)
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(cancel, isCancel: true)
        return dialog.run() == 0
    }

    static func show(error: Error) {
        let dialog = ClassicDialog(title: "Fehler", message: error.localizedDescription, warning: true)
        dialog.addButton("OK", isDefault: true, isCancel: true)
        _ = dialog.run()
    }

    static func info(title: String, message: String) {
        let dialog = ClassicDialog(title: title, message: message)
        dialog.addButton("OK", isDefault: true, isCancel: true)
        _ = dialog.run()
    }

    static func conflict(_ info: ConflictInfo) -> ConflictChoice {
        let dialog = ClassicDialog(title: "Datei existiert bereits", message: "\(info.path)\n\nNeu: \(describe(info.source))\nAlt: \(describe(info.existing))", warning: true)
        dialog.addButton("Überschreiben", isDefault: true)
        dialog.addButton("Alle überschreiben")
        dialog.addButton("Überspringen")
        dialog.addButton("Alle überspringen")
        dialog.addButton("Abbrechen", isCancel: true)
        switch dialog.run() {
        case 0: return .overwrite
        case 1: return .overwriteAll
        case 2: return .skip
        case 3: return .skipAll
        default: return .cancel
        }
    }

    static func failure(path: String, error: Error) -> FailureChoice {
        let dialog = ClassicDialog(title: "Fehler bei \(PosixPath.name(path))", message: error.localizedDescription, warning: true)
        dialog.addButton("Überspringen", isDefault: true)
        dialog.addButton("Alle überspringen")
        dialog.addButton("Abbrechen", isCancel: true)
        switch dialog.run() {
        case 0: return .skip
        case 1: return .skipAll
        default: return .abort
        }
    }

    static func askToSave(name: String) -> NSApplication.ModalResponse {
        let dialog = ClassicDialog(title: "Ungespeicherte Änderungen", message: "„\(name)“ wurde geändert. Änderungen speichern?")
        dialog.addButton("Speichern", isDefault: true)
        dialog.addButton("Nicht speichern")
        dialog.addButton("Abbrechen", isCancel: true)
        switch dialog.run() {
        case 0: return .alertFirstButtonReturn
        case 1: return .alertSecondButtonReturn
        default: return .alertThirdButtonReturn
        }
    }

    private static func describe(_ entry: FileEntry) -> String {
        "\(Formatting.exactSize(entry.size)), \(Formatting.date(entry.modified))"
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

    func requestPassword(_ prompt: String, account: String) -> PasswordEntry? {
        onMain { Dialogs.password(prompt) }
    }

    func storedPassword(for account: String) -> String? {
        Keychain.password(for: account)
    }

    func savePassword(_ password: String, for account: String) {
        Keychain.save(password, for: account)
    }

    func deletePassword(for account: String) {
        Keychain.delete(account: account)
    }

    private func onMain<T>(_ work: () -> T) -> T {
        Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work)
    }
}
