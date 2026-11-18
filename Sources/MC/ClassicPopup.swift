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
