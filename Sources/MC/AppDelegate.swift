import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private var pendingPaths: [String] = []
    private var pendingEdits: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        if !Bundle.main.bundlePath.hasSuffix(".app") { NSApp.applicationIconImage = Bundle.module.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:)) }
        let startPaths = CommandLine.arguments.dropFirst().map { ($0 as NSString).expandingTildeInPath }
        mainWindow = MainWindowController(startPaths: Array(startPaths.prefix(2)))
        mainWindow?.showWindow(nil)
        if !pendingPaths.isEmpty { mainWindow?.open(paths: pendingPaths) }
        pendingEdits.forEach { mainWindow?.edit(path: $0) }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL).map(\.path)
        if !files.isEmpty {
            if let mainWindow { mainWindow.open(paths: files) } else { pendingPaths += files }
        }
        for url in urls where url.scheme == "moonlight-commander" && url.host == "edit" {
            let paths = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "path" }.compactMap(\.value) ?? []
            for path in paths {
                if let mainWindow { mainWindow.edit(path: path) } else { pendingEdits.append(path) }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Settings.confirmExit, !Dialogs.confirm(title: "Moonlight Commander beenden?", message: "", confirm: "Beenden") { return .terminateCancel }
        guard mainWindow?.hasUnsavedEditors == true else { return .terminateNow }
        let proceed = Dialogs.confirm(title: "Ungespeicherte Änderungen", message: "In geöffneten Editor-Fenstern gibt es ungespeicherte Änderungen. Trotzdem beenden?", confirm: "Beenden", destructive: true)
        return proceed ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindow?.saveState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
