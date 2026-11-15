import Foundation

/// How much the notch is allowed to intrude right now.
public enum Presence: Equatable {
    /// Alerts, sounds and approval cards as usual.
    case normal
    /// No alerts, sounds or automatic drop-downs; the resting wings stay visible, so state is still one glance away.
    case quiet
    /// Not drawn at all (a full-screen app, such as a film, is in front).
    case hidden
}

/// Decides the notch's `Presence` from the user's preferences and what the screen is doing.
public struct QuietPolicy: Equatable {
    /// Disappear completely while a full-screen app is in front.
    public var quietInFullScreen: Bool
    /// Don't drop approval cards down over the app they are about to be answered in.
    public var quietWhenClaudeInFront: Bool
    /// Manual "pause alerts" until this time.
    public var pausedUntil: Date?

    public init(quietInFullScreen: Bool = true, quietWhenClaudeInFront: Bool = true, pausedUntil: Date? = nil) {
        self.quietInFullScreen = quietInFullScreen
        self.quietWhenClaudeInFront = quietWhenClaudeInFront
        self.pausedUntil = pausedUntil
    }

    /// The Claude desktop app, where Claude shows its own approval dialog. Terminals are deliberately not here: a
    /// terminal in front says nothing about whether the session that is asking is the one on screen.
    static let claudeSurfaces: Set<String> = ["com.anthropic.claudefordesktop"]

    /// Whether approval cards should wait quietly (a badge on the notch, no sound or drop-down) because the app in
    /// front already shows Claude's own prompt.
    public func holdsApprovals(frontmostBundleID: String?) -> Bool {
        guard quietWhenClaudeInFront, let id = frontmostBundleID else { return false }
        return Self.claudeSurfaces.contains(id)
    }

    public func presence(fullScreenActive: Bool, now: Date) -> Presence {
        if fullScreenActive && quietInFullScreen { return .hidden }
        return isPaused(at: now) ? .quiet : .normal
    }

    public func isPaused(at now: Date) -> Bool {
        pausedUntil.map { $0 > now } ?? false
    }
}
