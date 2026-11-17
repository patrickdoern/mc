import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let startPaths = CommandLine.arguments.dropFirst().map { ($0 as NSString).expandingTildeInPath }
        mainWindow = MainWindowController(startPaths: Array(startPaths.prefix(2)))
        mainWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Settings.confirmExit, !Dialogs.confirm(title: "macOS Commander beenden?", message: "", confirm: "Beenden") { return .terminateCancel }
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
