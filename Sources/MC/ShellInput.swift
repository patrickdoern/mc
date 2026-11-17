import AppKit
import Foundation

final class ShellInput {
    private(set) var text = ""
    var onChange: (() -> Void)?

    private var history: [String] = []
    private var historyIndex: Int?

    var isEmpty: Bool { text.isEmpty }

    func append(_ string: String) {
        text += string
        onChange?()
    }

    func deleteLast() {
        text = String(text.dropLast())
        onChange?()
    }

    func replace(with command: String) {
        text = command
        historyIndex = nil
        onChange?()
    }

    var entries: [String] { history }

    func clear() {
        text = ""
        historyIndex = nil
        onChange?()
    }

    func remember(_ command: String) {
        history.removeAll { $0 == command }
        history.append(command)
        historyIndex = nil
    }

    func recallPrevious() {
        guard !history.isEmpty else { return }
        let index = max((historyIndex ?? history.count) - 1, 0)
        historyIndex = index
        text = history[index]
        onChange?()
    }

    func recallNext() {
        guard let current = historyIndex else { return }
        if current + 1 < history.count {
            historyIndex = current + 1
            text = history[current + 1]
        } else {
            clear()
        }
        onChange?()
    }
}

final class ShellInputView: NSView {
    private let commandLine: ShellInput
    private let promptProvider: () -> String

    init(commandLine: ShellInput, prompt: @escaping () -> String) {
        self.commandLine = commandLine
        promptProvider = prompt
        super.init(frame: .zero)
        commandLine.onChange = { [weak self] in self?.needsDisplay = true }
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.commandBackground.setFill()
        bounds.fill()
        let prompt = promptProvider() + "> "
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.font, .foregroundColor: Theme.commandText]
        let available = Int((bounds.width - 12) / Theme.font.maximumAdvancement.width) - 1
        let visible = String((prompt + commandLine.text).suffix(max(available, 1)))
        (visible as NSString).draw(at: NSPoint(x: 6, y: 3), withAttributes: attributes)
        let caretX = 6 + (visible as NSString).size(withAttributes: attributes).width
        Theme.commandText.setFill()
        NSRect(x: caretX, y: 3, width: Theme.font.maximumAdvancement.width, height: 15).fill()
    }
}
