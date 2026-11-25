import AppKit
import MCCore

final class ShareDialog {
    private struct Request {
        let id: UUID
        let name: String
        let code: String
    }

    private static weak var running: ShareDialog?

    private let name: String
    private let folders: [String]
    private var server: LinkServer?
    private var dialog: ClassicDialog?
    private var status = localized("Wartet auf Verbindung")
    private var request: Request?
    private var failure: Error?

    private init(name: String, folders: [String]) {
        self.name = name
        self.folders = folders
    }

    static func run(adding model: PanelModel) {
        guard let setup = configure(adding: model) else { return }
        let identity: LinkIdentity
        do {
            identity = try LinkIdentity.load()
        } catch {
            return Dialogs.show(error: error)
        }
        let dialog = ShareDialog(name: setup.name, folders: setup.folders)
        dialog.share(identity: identity)
    }

    static func stopRunning() {
        running?.server?.stop()
    }

    private static func configure(adding model: PanelModel) -> (name: String, folders: [String])? {
        var name = Settings.linkName
        var folders = Settings.linkFolders
        var selected = 0
        while true {
            let dialog = ClassicDialog(title: localized("Freigeben"), message: localized("Ein anderer Mac mit Moonlight Commander kann diese Ordner im lokalen Netz lesen, solange die Freigabe läuft."))
            let field = dialog.addText(label: localized("Anzeigename:"), value: name)
            let choice = folders.isEmpty ? nil : dialog.addChoice(label: localized("Ordner"), options: folders, selected: selected)
            dialog.addButton(localized("Freigeben"), isDefault: true)
            dialog.addButton(localized("Hinzufügen"))
            if choice != nil { dialog.addButton(localized("Entfernen")) }
            dialog.addButton(localized("Abbrechen"), isCancel: true)
            let pressed = dialog.run()
            name = field.stringValue.trimmingCharacters(in: .whitespaces)
            selected = choice.map(dialog.choice) ?? 0
            switch pressed {
            case 0:
                if let problem = problem(name: name, folders: folders) {
                    Dialogs.show(error: FileError(problem))
                    continue
                }
                Settings.linkName = name
                Settings.linkFolders = folders
                return (name, folders)
            case 1:
                if let problem = problem(adding: model) {
                    Dialogs.show(error: FileError(problem))
                } else if let index = folders.firstIndex(of: model.path) {
                    selected = index
                } else {
                    folders.append(model.path)
                    selected = folders.count - 1
                }
            case 2 where choice != nil:
                folders.remove(at: selected)
                selected = max(min(selected, folders.count - 1), 0)
            default:
                return nil
            }
        }
    }

    private static func problem(name: String, folders: [String]) -> String? {
        if name.isEmpty { return localized("Bitte einen Anzeigenamen eingeben") }
        if name.utf8.count > 63 { return localized("Der Anzeigename ist zu lang (höchstens 63 Bytes)") }
        if folders.isEmpty { return localized("Ohne Ordner lässt sich nicht freigeben. „Hinzufügen“ übernimmt den Ordner des aktiven Panels.") }
        return nil
    }

    private static func problem(adding model: PanelModel) -> String? {
        if !model.isLocal { return localized("Nur lokale Ordner lassen sich freigeben, keine Server, Archive oder Suchergebnisse") }
        if model.path == "/" { return localized("Der ganze Mac (/) lässt sich nicht freigeben") }
        return nil
    }

    private func share(identity: LinkIdentity) {
        let server = LinkServer(name: name, folders: folders, writable: false, identity: identity) { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
        do {
            try server.start()
        } catch {
            return Dialogs.show(error: Self.startFailure(error))
        }
        self.server = server
        Self.running = self
        while failure == nil {
            let shown = request
            let dialog = makeDialog(for: shown)
            self.dialog = dialog
            let pressed = dialog.run()
            self.dialog = nil
            if let shown {
                guard let pressed else { continue }
                server.decide(shown.id, allow: pressed == 0)
                if request?.id == shown.id { request = nil }
            } else if pressed != nil {
                break
            }
        }
        server.stop()
        Self.running = nil
        if let failure { Dialogs.show(error: Self.startFailure(failure)) }
    }

    private func makeDialog(for request: Request?) -> ClassicDialog {
        guard let request else {
            let dialog = ClassicDialog(title: localized("Freigabe"), message: message)
            dialog.addButton(localized("Freigabe beenden"), isDefault: true, isCancel: true)
            return dialog
        }
        let dialog = ClassicDialog(title: localized("Freigabe"), message: localized("%@ möchte sich verbinden. Code: %@", request.name as NSString, request.code as NSString) + "\n\n" + localized("Nur zulassen, wenn der andere Mac denselben Code zeigt."))
        dialog.addButton(localized("Zulassen"), isDefault: true)
        dialog.addButton(localized("Ablehnen"), isCancel: true)
        return dialog
    }

    private var message: String {
        ([localized("Freigegeben als „%@“:", name as NSString)] + folders.map { ($0 as NSString).abbreviatingWithTildeInPath } + ["", status]).joined(separator: "\n")
    }

    private func handle(_ event: LinkServer.Event) {
        switch event {
        case .waiting:
            show(localized("Wartet auf Verbindung"))
        case .request(let id, let name, let code):
            request = Request(id: id, name: name, code: code)
            dialog?.interrupt()
        case .requestExpired:
            guard request != nil else { return }
            request = nil
            dialog?.interrupt()
        case .connected(let peer):
            show(localized("Verbunden mit %@", peer as NSString))
        case .reading(let peer, let path):
            show(localized("%@ liest %@", peer as NSString, PosixPath.name(path) as NSString))
        case .writing(let peer, let path):
            show(localized("%@ schreibt %@", peer as NSString, PosixPath.name(path) as NSString))
        case .deleting(let peer, let path):
            show(localized("%@ löscht %@", peer as NSString, PosixPath.name(path) as NSString))
        case .changing(let peer, let path):
            show(localized("%@ ändert %@", peer as NSString, PosixPath.name(path) as NSString))
        case .incompatible(let peer):
            show(peer + ": " + localized("Die Gegenstelle hat eine andere Version von Moonlight Commander"))
        case .failed(let error):
            failure = error
            dialog?.interrupt()
        }
    }

    private func show(_ text: String) {
        status = text
        if request == nil { dialog?.setMessage(message) }
    }

    private static func startFailure(_ error: Error) -> FileError {
        FileError(localized("Die Freigabe konnte nicht gestartet werden: %@", error.localizedDescription as NSString) + "\n\n" + localized("Erlaube Moonlight Commander den Zugriff unter Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk."))
    }
}
