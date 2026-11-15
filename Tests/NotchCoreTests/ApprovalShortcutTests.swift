import XCTest
@testable import NotchCore

final class ApprovalShortcutTests: XCTestCase {
    private let now = Fixture.t0

    private func action(waiting: Bool = true, showing: Bool = true, hidden: Bool = false, last: Date? = nil) -> ApprovalShortcut.Action {
        ApprovalShortcut.action(requestsWaiting: waiting, cardsShowing: showing, hidden: hidden, lastAnswer: last, now: now)
    }

    func testAnswersTheOldestRequestWhenTheCardsAreOnScreen() {
        XCTAssertEqual(action(), .answer)
    }

    func testHeldBackCardsAreRevealedFirstNeverAnsweredBlind() {
        XCTAssertEqual(action(showing: false), .reveal)
    }

    func testNothingWaitingOrNotchHiddenDoesNothing() {
        XCTAssertEqual(action(waiting: false), .ignore)
        XCTAssertEqual(action(hidden: true), .ignore)
    }

    func testAFumbledDoublePressDoesNotAnswerTheNextCardUnseen() {
        XCTAssertEqual(action(last: now.addingTimeInterval(-0.3)), .ignore)
        XCTAssertEqual(action(last: now.addingTimeInterval(-ApprovalShortcut.minimumGap - 0.1)), .answer)
    }
}
