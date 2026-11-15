import Foundation

public enum SessionState: String, CaseIterable {
    case needsYou, working, done, idle

    public var label: String {
        switch self {
        case .needsYou: return "Needs you"
        case .working: return "Working"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }

    /// Lower sorts first in the list.
    var sortPriority: Int {
        switch self {
        case .needsYou: return 0
        case .working: return 1
        case .done: return 2
        case .idle: return 3
        }
    }
}

/// When a session's prompt cache goes cold. An estimate: the API never reports an expiry time.
public struct PromptCache: Equatable {
    public let expiresAt: Date
    /// 1-hour cache rather than the default 5-minute one.
    public let isLongLived: Bool

    public var lifetime: TimeInterval { isLongLived ? Config.longCacheLifetime : Config.shortCacheLifetime }
    public var warningThreshold: TimeInterval { isLongLived ? Config.longCacheWarning : Config.shortCacheWarning }
    public var countdownThreshold: TimeInterval { isLongLived ? Config.longCacheCountdown : Config.shortCacheCountdown }

    public func remaining(at now: Date) -> TimeInterval { expiresAt.timeIntervalSince(now) }
    /// 1 when freshly written, 0 when cold.
    public func fractionRemaining(at now: Date) -> Double { max(0, min(1, remaining(at: now) / lifetime)) }
}

public struct ContextUsage: Equatable {
    public var tokens: Int
    public var window: Int
    /// True right after `/compact`, when the figure is estimated from the summary rather than reported.
    public var isEstimate: Bool = false

    public var fraction: Double { min(1, Double(tokens) / Double(max(1, window))) }
    public var percent: Int { Int(fraction * 100) }
    /// For example `212k / 1M · 21%`, with a leading `~` for estimates.
    public var label: String {
        "\(isEstimate ? "~" : "")\(Format.tokens(tokens)) / \(Format.tokens(window)) · \(percent)%"
    }
}

public struct ClaudeSession: Identifiable, Equatable {
    /// The transcript's session id (the `.jsonl` file name).
    public let id: String
    public var title: String
    public var project: String
    public var state: SessionState
    /// What it is doing right now, or its last words.
    public var detail: String
    /// Time of the last real message (not of metadata writes).
    public var lastActivity: Date
    public var cache: PromptCache?
    public var context: ContextUsage
    public var model: String
}
