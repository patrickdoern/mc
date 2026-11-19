import AppKit

final class AboutPanel: NSObject {
    static let shared = AboutPanel()

    static let website = URL(string: "https://moonlight-commander.de")!
    static let imprint = URL(string: "https://moonlight-commander.de/impressum")!

    @objc func show() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let credits = NSMutableAttributedString(string: "Zwei-Panel-Dateimanager im Stil des Norton Commander.\nKostenlos, ohne Werbung und ohne Datenerfassung.\n\nEntwickelt von Patrick Dörn\n", attributes: body)
        credits.append(NSAttributedString(string: "moonlight-commander.de", attributes: body.merging([.link: Self.website]) { $1 }))
        credits.append(NSAttributedString(string: "\n\nEnthält freie Software:\nlibssh2 (BSD-Lizenz) · OpenSSL (Apache-2.0)\nSwiftTerm (MIT) · libcurl (curl-Lizenz)\n\n„Norton Commander“ und „Midnight Commander“ sind Namen ihrer jeweiligen Inhaber. Diese App steht in keiner Verbindung zu ihnen.", attributes: body))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openImprint() {
        NSWorkspace.shared.open(Self.imprint)
    }
}
