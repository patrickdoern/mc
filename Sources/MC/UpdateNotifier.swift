import AppKit
import MCCore

final class UpdateNotifier: NSObject {
    static let shared = UpdateNotifier()

    private static let interval: TimeInterval = 24 * 60 * 60

    private var installedVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    func checkOnLaunch() {
        guard let installed = installedVersion else { return }
        if Settings.updateCheck == .unasked {
            let allowed = Dialogs.confirm(
                title: localized("Nach Updates suchen"),
                message: localized("Beim Start nach neuen Versionen suchen?") + "\n\n" + localized("Dazu wird api.github.com kontaktiert. Es werden keine persönlichen Daten gesendet. Das lässt sich unter Konfiguration jederzeit ändern."),
                confirm: localized("Ja"),
                cancel: localized("Nein")
            )
            Settings.updateCheck = allowed ? .enabled : .disabled
        }
        guard Settings.updateCheck == .enabled else { return }
        if let last = Settings.lastUpdateCheck, Date().timeIntervalSince(last) < Self.interval { return }
        Settings.lastUpdateCheck = Date()
        Task { @MainActor in
            guard case .newer(let release)? = try? await UpdateCheck.check(installedVersion: installed),
                  Settings.shownUpdateVersion != release.tag
            else { return }
            Settings.shownUpdateVersion = release.tag
            offer(release, installed: installed)
        }
    }

    @objc func checkNow() {
        guard let installed = installedVersion else {
            Dialogs.info(title: localized("Nach Updates suchen"), message: localized("Version unbekannt (Entwicklungsbuild)"))
            return
        }
        Task { @MainActor in
            do {
                switch try await UpdateCheck.check(installedVersion: installed) {
                case .newer(let release): offer(release, installed: installed)
                case .upToDate: Dialogs.info(title: localized("Nach Updates suchen"), message: localized("Du hast die neueste Version."))
                }
            } catch {
                Dialogs.show(error: error)
            }
        }
    }

    private func offer(_ release: ReleaseInfo, installed: String) {
        let version = release.tag.hasPrefix("v") ? String(release.tag.dropFirst()) : release.tag
        let open = Dialogs.confirm(
            title: localized("Update verfügbar"),
            message: localized("Version %@ ist verfügbar (installiert: %@).", version as NSString, installed as NSString),
            confirm: localized("Download-Seite"),
            cancel: localized("Später")
        )
        if open { NSWorkspace.shared.open(release.url) }
    }
}
