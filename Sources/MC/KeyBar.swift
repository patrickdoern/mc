import AppKit

final class KeyBar: NSView {
    init(labels: [String], onPress: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        let buttons = labels.enumerated().map { index, label in KeyBarButton(number: index + 1, label: label) { onPress(index + 1) } }
        let stack = NSStackView(views: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyBarBackground.setFill()
        bounds.fill()
    }
}

private final class KeyBarButton: NSView {
    private let number: Int
    private let label: String
    private let action: () -> Void

    init(number: Int, label: String, action: @escaping () -> Void) {
        self.number = number
        self.label = label
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyBarBackground.setFill()
        bounds.fill()
        let digits = String(number)
        let digitsWidth = (digits as NSString).size(withAttributes: [.font: Theme.font]).width
        (digits as NSString).draw(at: NSPoint(x: 2, y: 2), withAttributes: [.font: Theme.font, .foregroundColor: Theme.keyBarNumber])
        let labelRect = NSRect(x: digitsWidth + 3, y: 0, width: max(bounds.width - digitsWidth - 3, 0), height: bounds.height)
        Theme.keyBarLabelBackground.setFill()
        labelRect.fill()
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        (label as NSString).draw(in: labelRect.insetBy(dx: 3, dy: 3), withAttributes: [.font: font, .foregroundColor: Theme.keyBarLabel])
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}
