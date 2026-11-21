import Testing
@testable import MCCore

@Suite struct NavigationHistoryTests {
    private func make(_ elements: [Int], limit: Int = 50) -> NavigationHistory<Int> {
        NavigationHistory(limit: limit, elements: elements)
    }

    @Test func startsEmpty() {
        var history = NavigationHistory<Int>()
        #expect(history.elements.isEmpty)
        #expect(history.position == -1)
        #expect(history.current == nil)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
        let previous = history.back()
        #expect(previous == nil)
        let next = history.forward()
        #expect(next == nil)
        let jumped = history.jump(to: 0)
        #expect(!jumped)
        history.remove(at: 0)
        #expect(history.position == -1)
    }

    @Test func recordsElements() {
        var history = NavigationHistory<Int>()
        history.record(1)
        history.record(2)
        #expect(history.elements == [1, 2])
        #expect(history.position == 1)
        #expect(history.current == 2)
    }

    @Test func ignoresDuplicateOfCurrent() {
        var history = make([1, 2])
        history.record(2)
        #expect(history.elements == [1, 2])
        #expect(history.position == 1)
    }

    @Test func recordsEqualElementThatIsNotCurrent() {
        var history = make([1, 2])
        history.record(1)
        #expect(history.elements == [1, 2, 1])
    }

    @Test func initKeepsLastElements() {
        let history = make([1, 2, 3, 4], limit: 3)
        #expect(history.elements == [2, 3, 4])
        #expect(history.position == 2)
        #expect(history.limit == 3)
    }

    @Test func recordAfterBackDropsForwardPart() {
        var history = make([1, 2, 3])
        _ = history.back()
        _ = history.back()
        history.record(9)
        #expect(history.elements == [1, 9])
        #expect(history.position == 1)
        #expect(!history.canGoForward)
    }

    @Test func recordAfterBackToSameElementKeepsForwardPart() {
        var history = make([1, 2, 3])
        _ = history.back()
        history.record(2)
        #expect(history.elements == [1, 2, 3])
        #expect(history.position == 1)
    }

    @Test func limitDropsOldestElement() {
        var history = make([1, 2, 3], limit: 3)
        history.record(4)
        #expect(history.elements == [2, 3, 4])
        #expect(history.position == 2)
        #expect(history.current == 4)
    }

    @Test func limitAfterBackKeepsPositionOnRecordedElement() {
        var history = make([1, 2, 3], limit: 3)
        _ = history.back()
        history.record(4)
        #expect(history.elements == [1, 2, 4])
        #expect(history.position == 2)
        history.record(5)
        #expect(history.elements == [2, 4, 5])
        #expect(history.position == 2)
    }

    @Test func defaultLimitIsFifty() {
        var history = NavigationHistory<Int>()
        for value in 0..<60 { history.record(value) }
        #expect(history.limit == 50)
        #expect(history.elements.count == 50)
        #expect(history.elements.first == 10)
        #expect(history.current == 59)
    }

    @Test func goesBackAndForward() {
        var history = make([1, 2, 3])
        let previous = history.back()
        #expect(previous == 2)
        #expect(history.position == 1)
        #expect(history.canGoBack)
        #expect(history.canGoForward)
        let previous2 = history.back()
        #expect(previous2 == 1)
        #expect(!history.canGoBack)
        let next = history.forward()
        #expect(next == 2)
        let next2 = history.forward()
        #expect(next2 == 3)
        #expect(!history.canGoForward)
    }

    @Test func endsReturnNilWithoutMoving() {
        var history = make([1, 2])
        let atEnd = history.forward()
        #expect(atEnd == nil)
        #expect(history.position == 1)
        _ = history.back()
        let atStart = history.back()
        #expect(atStart == nil)
        #expect(history.position == 0)
    }

    @Test func jumpsToValidIndex() {
        var history = make([1, 2, 3])
        let jumped = history.jump(to: 0)
        #expect(jumped)
        #expect(history.position == 0)
        #expect(history.current == 1)
        let jumped2 = history.jump(to: 2)
        #expect(jumped2)
        #expect(history.current == 3)
    }

    @Test func jumpToInvalidIndexChangesNothing() {
        var history = make([1, 2, 3])
        let rejected = history.jump(to: 3)
        #expect(!rejected)
        let rejectedNegative = history.jump(to: -1)
        #expect(!rejectedNegative)
        #expect(history.position == 2)
    }

    @Test func removeBeforePositionShiftsPosition() {
        var history = make([1, 2, 3])
        history.remove(at: 0)
        #expect(history.elements == [2, 3])
        #expect(history.position == 1)
        #expect(history.current == 3)
    }

    @Test func removeAtPositionKeepsIndex() {
        var history = make([1, 2, 3])
        _ = history.back()
        history.remove(at: 1)
        #expect(history.elements == [1, 3])
        #expect(history.position == 1)
        #expect(history.current == 3)
    }

    @Test func removeAtLastPositionClampsPosition() {
        var history = make([1, 2, 3])
        history.remove(at: 2)
        #expect(history.elements == [1, 2])
        #expect(history.position == 1)
    }

    @Test func removeAfterPositionKeepsPosition() {
        var history = make([1, 2, 3])
        _ = history.back()
        history.remove(at: 2)
        #expect(history.elements == [1, 2])
        #expect(history.position == 1)
    }

    @Test func removeLastElementEmptiesHistory() {
        var history = make([1])
        history.remove(at: 0)
        #expect(history.elements.isEmpty)
        #expect(history.position == -1)
        #expect(history.current == nil)
    }

    @Test func removeInvalidIndexChangesNothing() {
        var history = make([1, 2])
        history.remove(at: 2)
        history.remove(at: -1)
        #expect(history.elements == [1, 2])
        #expect(history.position == 1)
    }
}
