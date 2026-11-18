import AppKit

enum ClassicPopup {
    static func show(_ menu: NSMenu, title: String?, in window: NSWindow?) {
        guard let window, let content = window.contentView else { return }
        let previous = window.firstResponder
        let view = DropdownView(menu: menu, title: title)
        let centerY = content.isFlipped ? content.bounds.midY - view.frame.height / 2 - 40 : content.bounds.midY - view.frame.height / 2 + 40
        view.frame.origin = NSPoint(x: content.bounds.midX - view.frame.width / 2, y: centerY)
        view.onDismiss = { [weak view] item in
            view?.removeFromSuperview()
            window.makeFirstResponder(previous)
            item?.perform()
        }
        content.addSubview(view)
        window.makeFirstResponder(view)
    }
}

private final class OverlayBlocker: NSView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
}

enum ClassicOverlay {
    static func present(_ dialog: NSView, in window: NSWindow) -> () -> Void {
        guard let content = window.contentView else { return {} }
        let previous = window.firstResponder
        let blocker = OverlayBlocker(frame: content.bounds)
        blocker.autoresizingMask = [.width, .height]
        content.addSubview(blocker)
        let offset: CGFloat = content.isFlipped ? -20 : 20
        dialog.frame.origin = NSPoint(x: content.bounds.midX - dialog.frame.width / 2, y: content.bounds.midY - dialog.frame.height / 2 + offset)
        dialog.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        dialog.wantsLayer = true
        dialog.layer?.shadowColor = NSColor.black.cgColor
        dialog.layer?.shadowOpacity = 0.45
        dialog.layer?.shadowRadius = 14
        dialog.layer?.shadowOffset = CGSize(width: 0, height: -4)
        content.addSubview(dialog)
        window.makeFirstResponder(dialog)
        return {
            dialog.removeFromSuperview()
            blocker.removeFromSuperview()
            window.makeFirstResponder(previous)
        }
    }
}
