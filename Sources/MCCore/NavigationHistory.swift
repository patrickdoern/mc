public struct NavigationHistory<Element: Equatable> {
    public let limit: Int
    public private(set) var elements: [Element]
    public private(set) var position: Int

    public init(limit: Int = 50, elements: [Element] = []) {
        self.limit = max(1, limit)
        self.elements = Array(elements.suffix(self.limit))
        position = self.elements.count - 1
    }

    public var current: Element? {
        elements.indices.contains(position) ? elements[position] : nil
    }

    public var canGoBack: Bool { position > 0 }

    public var canGoForward: Bool { position < elements.count - 1 }

    public mutating func record(_ element: Element) {
        if element == current { return }
        elements.removeSubrange((position + 1)...)
        elements.append(element)
        if elements.count > limit {
            elements.removeFirst(elements.count - limit)
        }
        position = elements.count - 1
    }

    public mutating func back() -> Element? {
        guard canGoBack else { return nil }
        position -= 1
        return elements[position]
    }

    public mutating func forward() -> Element? {
        guard canGoForward else { return nil }
        position += 1
        return elements[position]
    }

    @discardableResult
    public mutating func jump(to index: Int) -> Bool {
        guard elements.indices.contains(index) else { return false }
        position = index
        return true
    }

    public mutating func remove(at index: Int) {
        guard elements.indices.contains(index) else { return }
        elements.remove(at: index)
        if index < position {
            position -= 1
        } else if index == position {
            position = min(position, elements.count - 1)
        }
    }
}
