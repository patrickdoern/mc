import Quartz

final class QuickLook: NSObject, QLPreviewPanelDataSource {
    private var url: URL?

    var isVisible: Bool { QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible }

    func show(_ url: URL) {
        self.url = url
        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func update(_ url: URL?) {
        guard isVisible, let url else { return }
        self.url = url
        QLPreviewPanel.shared().reloadData()
    }

    func hide() {
        QLPreviewPanel.shared().orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! { url as NSURL? }
}
