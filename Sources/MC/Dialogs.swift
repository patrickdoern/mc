import AppKit
import MCCore

enum Dialogs {
    static func prompt(title: String, message: String, value: String = "", confirm: String = localized("OK"), history: [String] = []) -> String? {
        let dialog = ClassicDialog(title: title, message: message)
        let field = dialog.addText(value: value)
        if !history.isEmpty { dialog.addChoice(label: localized("Verlauf"), options: history, selected: 0) { field.stringValue = $0 } }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        let result = field.stringValue.trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? nil : result
    }

    struct FormResult {
        let choice: Int
        let checks: [Bool]
    }

    static func form(title: String, message: String = "", popup: (label: String, options: [String], selected: Int)? = nil, checks: [(title: String, value: Bool)] = [], confirm: String = localized("OK")) -> FormResult? {
        let dialog = ClassicDialog(title: title, message: message)
        let choiceItem = popup.map { dialog.addChoice(label: $0.label, options: $0.options, selected: $0.selected) }
        let checkItems = checks.map { dialog.addCheck($0.title, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return FormResult(choice: choiceItem.map(dialog.choice) ?? 0, checks: checkItems.map(dialog.isChecked))
    }

    static func fields(title: String, message: String = "", fields: [(label: String, value: String)], confirm: String = localized("OK")) -> [String]? {
        let dialog = ClassicDialog(title: title, message: message)
        let inputs = fields.map { dialog.addText(label: $0.label, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return inputs.map { $0.stringValue.trimmingCharacters(in: .whitespaces) }
    }

    static func searchForm(title: String, fields: [(label: String, value: String)], checks: [(title: String, value: Bool)], message: String = "", confirm: String) -> (values: [String], checks: [Bool])? {
        let dialog = ClassicDialog(title: title, message: message)
        let inputs = fields.map { dialog.addText(label: $0.label, value: $0.value) }
        let checkItems = checks.map { dialog.addCheck($0.title, value: $0.value) }
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return (inputs.map(\.stringValue), checkItems.map(dialog.isChecked))
    }

    static func secret(_ message: String) -> String? {
        let dialog = ClassicDialog(title: localized("Eingabe"), message: message)
        let field = dialog.addText(secure: true)
        dialog.addButton(localized("OK"), isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        return dialog.run() == 0 ? field.stringValue : nil
    }

    static func password(_ message: String) -> PasswordEntry? {
        let dialog = ClassicDialog(title: localized("Passwort"), message: message)
        let field = dialog.addText(secure: true)
        let remember = dialog.addCheck(localized("Im Schlüsselbund sichern"), value: false)
        dialog.addButton(localized("OK"), isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        return PasswordEntry(password: field.stringValue, remember: dialog.isChecked(remember))
    }

    static func confirm(title: String, message: String, confirm: String, cancel: String = localized("Abbrechen"), destructive: Bool = false) -> Bool {
        let dialog = ClassicDialog(title: title, message: message, warning: destructive)
        dialog.addButton(confirm, isDefault: true)
        dialog.addButton(cancel, isCancel: true)
        return dialog.run() == 0
    }

    static func show(error: Error) {
        let dialog = ClassicDialog(title: localized("Fehler"), message: error.localizedDescription, warning: true)
        dialog.addButton(localized("OK"), isDefault: true, isCancel: true)
        _ = dialog.run()
    }

    static func info(title: String, message: String) {
        let dialog = ClassicDialog(title: title, message: message)
        dialog.addButton(localized("OK"), isDefault: true, isCancel: true)
        _ = dialog.run()
    }

    static func transfer(title: String, message: String, value: String, options: TransferOptions) -> (text: String, options: TransferOptions)? {
        let dialog = ClassicDialog(title: title, message: message)
        let field = dialog.addText(value: value)
        let rule = dialog.addChoice(label: localized("Bei vorhandener Datei:"), options: [localized("Jedes Mal fragen"), localized("Überschreiben"), localized("Nur wenn neuer"), localized("Nur wenn Größe abweicht"), localized("Überspringen")], selected: options.overwriteRule.rawValue)
        let preserve = dialog.addCheck(localized("Attribute erhalten"), value: options.preserveAttributes)
        let follow = dialog.addCheck(localized("Symbolischen Links folgen"), value: options.followSymlinks)
        dialog.addButton(title, isDefault: true)
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        guard dialog.run() == 0 else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let chosen = TransferOptions(overwriteRule: OverwriteRule(rawValue: dialog.choice(rule)) ?? .ask, preserveAttributes: dialog.isChecked(preserve), followSymlinks: dialog.isChecked(follow))
        return (text, chosen)
    }

    static func conflict(_ info: ConflictInfo) -> ConflictChoice {
        let dialog = ClassicDialog(title: localized("Datei existiert bereits"), message: info.path + "\n\n" + localized("Neu: %@", describe(info.source) as NSString) + "\n" + localized("Alt: %@", describe(info.existing) as NSString), warning: true)
        let rule = dialog.addChoice(label: localized("Für alle weiteren:"), options: [localized("Jedes Mal fragen"), localized("Nur wenn neuer"), localized("Nur wenn Größe abweicht")], selected: 0)
        dialog.addButton(localized("Überschreiben"), isDefault: true)
        dialog.addButton(localized("Alle überschreiben"))
        dialog.addButton(localized("Überspringen"))
        dialog.addButton(localized("Alle überspringen"))
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        let button = dialog.run()
        let further: OverwriteRule? = [nil, .ifNewer, .ifSizeDiffers][dialog.choice(rule)]
        switch button {
        case 0: return further.map(ConflictChoice.overwriteThenRule) ?? .overwrite
        case 1: return .overwriteAll
        case 2: return further.map(ConflictChoice.skipThenRule) ?? .skip
        case 3: return .skipAll
        default: return .cancel
        }
    }

    static func failure(path: String, error: Error) -> FailureChoice {
        let dialog = ClassicDialog(title: localized("Fehler bei %@", PosixPath.name(path) as NSString), message: error.localizedDescription, warning: true)
        dialog.addButton(localized("Überspringen"), isDefault: true)
        dialog.addButton(localized("Alle überspringen"))
        dialog.addButton(localized("Abbrechen"), isCancel: true)
        switch dialog.run() {
        case 0: return .skip
        case 1: return .skipAll
        default: return .abort
        }
    }

    static func askToSave(name: String) -> NSApplication.ModalResponse {
        let dialog = ClassicDialog(title: localized("Ungespeicherte Änderungen"), message: localized("„%@“ wurde geändert. Änderungen speichern?", name as NSString))
        dialog.addButton(localized("Speichern"), isDefault: true)
        dialog.addButton(localized("Nicht speichern"))
        dialog.addButton(localized("Abbrechen"), isCancel: true)
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
                title: localized("Unbekannter Host %@", host as NSString),
                message: localized("Der %@-Schlüssel dieses Servers ist noch nicht bekannt.", keyType as NSString) + "\n" + fingerprint + "\n\n" + localized("Verbindung herstellen und Schlüssel in known_hosts speichern?"),
                confirm: localized("Vertrauen")
            )
        }
    }

    func allowUnencryptedLogin(_ host: String) -> Bool {
        onMain {
            Dialogs.confirm(
                title: localized("Keine Verschlüsselung bei %@", host as NSString),
                message: localized("Der Server bietet kein TLS an. Benutzername und Passwort würden unverschlüsselt übertragen.") + "\n\n" + localized("Trotzdem unverschlüsselt anmelden?"),
                confirm: localized("Unverschlüsselt anmelden"),
                destructive: true
            )
        }
    }

    func trustCertificate(_ host: String, certificate: FTPCertificate, changed: Bool) -> Bool {
        var lines = [changed ? localized("Das Zertifikat dieses Servers hat sich geändert. Das kann ein Angriff sein oder ein erneuertes Zertifikat.") : localized("Das Zertifikat dieses Servers ist keiner bekannten Zertifizierungsstelle zugeordnet, z. B. weil es selbstsigniert ist.")]
        if let subject = certificate.subject { lines.append(localized("Inhaber: %@", subject as NSString)) }
        if let issuer = certificate.issuer { lines.append(localized("Aussteller: %@", issuer as NSString)) }
        if let expires = certificate.expires { lines.append(localized("Gültig bis: %@", expires as NSString)) }
        lines.append("SHA256: " + certificate.fingerprint)
        return onMain {
            Dialogs.confirm(
                title: changed ? localized("Zertifikat von %@ geändert", host as NSString) : localized("Unbekanntes Zertifikat von %@", host as NSString),
                message: lines.joined(separator: "\n") + "\n\n" + localized("Diesem Zertifikat vertrauen und es für künftige Verbindungen speichern?"),
                confirm: localized("Vertrauen"),
                destructive: changed
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
