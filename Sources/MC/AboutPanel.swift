import AppKit

final class AboutPanel: NSObject {
    static let shared = AboutPanel()

    static let website = URL(string: "https://moonlight-commander.de")!
    static let licenses = URL(string: "https://moonlight-commander.de/lizenzen")!
    static let imprint = URL(string: "https://moonlight-commander.de/impressum")!

    @objc func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let link: [NSAttributedString.Key: Any] = body.merging([.link: Self.website]) { $1 }
        let licenses: [NSAttributedString.Key: Any] = body.merging([.link: Self.licenses]) { $1 }
        let credits = NSMutableAttributedString(string: "Zwei-Panel-Dateimanager für macOS\nKostenlos, ohne Werbung und Tracking\n\nEntwickelt von Patrick Dörn\n", attributes: body)
        credits.append(NSAttributedString(string: "moonlight-commander.de", attributes: link))
        credits.append(NSAttributedString(string: "\n\n", attributes: body))
        credits.append(NSAttributedString(string: "Lizenzen der enthaltenen Software", attributes: licenses))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openImprint() {
        NSWorkspace.shared.open(Self.imprint)
    }
}
