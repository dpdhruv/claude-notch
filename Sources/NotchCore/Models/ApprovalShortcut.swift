import Foundation

/// What a keyboard shortcut for Allow / Deny should do, decided so that nothing is ever approved unseen.
public enum ApprovalShortcut {
    public enum Action: Equatable {
        /// Nothing to answer, or the notch is hidden (a full-screen app is in front).
        case ignore
        /// The cards are held back: the first press shows them, so you see what you are about to answer.
        case reveal
        /// The cards are on screen: answer the oldest one.
        case answer
    }

    /// Two answers closer together than this are one fumbled double-press: the next card has just slid in unseen.
    public static let minimumGap: TimeInterval = 0.8

    public static func action(requestsWaiting: Bool, cardsShowing: Bool, hidden: Bool,
                              lastAnswer: Date?, now: Date) -> Action {
        guard requestsWaiting, !hidden else { return .ignore }
        guard cardsShowing else { return .reveal }
        if let lastAnswer, now.timeIntervalSince(lastAnswer) < minimumGap { return .ignore }
        return .answer
    }
}
