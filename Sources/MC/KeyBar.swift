import AppKit

final class KeyBar: NSView {
    private let buttons: [KeyBarButton]

    init(labels: [String], shortLabels: [String], onPress: @escaping (Int) -> Void) {
        buttons = labels.indices.map { index in KeyBarButton(number: index + 1, label: labels[index], shortLabel: shortLabels[index]) { onPress(index + 1) } }
        super.init(frame: .zero)
        let stack = NSStackView(views: buttons)
        stack.distribution = .fillEqually
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Theme.didChange, object: nil)
    }

    @objc private func themeDidChange(_ notification: Notification) {
        needsDisplay = true
        buttons.forEach { $0.needsDisplay = true }
    }

    func setLabel(_ number: Int, label: String, shortLabel: String) {
        buttons[number - 1].label = label
        buttons[number - 1].shortLabel = shortLabel
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        Theme.keyBarLabelBackground.setFill()
        bounds.fill()
    }
}

private final class KeyBarButton: NSView {
    private let number: Int
    var label: String { didSet { needsDisplay = true } }
    var shortLabel: String { didSet { needsDisplay = true } }
    private let action: () -> Void

    init(number: Int, label: String, shortLabel: String, action: @escaping () -> Void) {
        self.number = number
        self.label = label
        self.shortLabel = shortLabel
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
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.keyBarLabel]
        let available = labelRect.width - 6
        let text = (label as NSString).size(withAttributes: attributes).width <= available ? label : shortLabel
        (text as NSString).draw(in: labelRect.insetBy(dx: 3, dy: 3), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        action()
    }
}
