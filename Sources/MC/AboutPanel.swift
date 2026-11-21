import AppKit
import MCCore

final class AboutPanel: NSObject {
    static let shared = AboutPanel()

    static let website = URL(string: "https://moonlight-commander.org")!
    static let licenses = URL(string: "https://moonlight-commander.org/lizenzen")!
    static let imprint = URL(string: "https://moonlight-commander.org/impressum")!

    @objc func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let link: [NSAttributedString.Key: Any] = body.merging([.link: Self.website]) { $1 }
        let licenses: [NSAttributedString.Key: Any] = body.merging([.link: Self.licenses]) { $1 }
        let credits = NSMutableAttributedString(string: localized("Zwei-Panel-Dateimanager für macOS") + "\n" + localized("Kostenlos, ohne Werbung und Tracking") + "\n\n" + localized("Entwickelt von Patrick Dörn") + "\n", attributes: body)
        credits.append(NSAttributedString(string: "moonlight-commander.org", attributes: link))
        credits.append(NSAttributedString(string: "\n\n", attributes: body))
        credits.append(NSAttributedString(string: localized("Lizenzen der enthaltenen Software"), attributes: licenses))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openImprint() {
        NSWorkspace.shared.open(Self.imprint)
    }
}
