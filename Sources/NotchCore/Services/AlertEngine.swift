import Foundation

/// Something worth pulling the notch down for.
public struct NotchAlert: Equatable {
    public enum Kind: Equatable { case needsYou, done, cacheLow, cacheCold, info }

    public let kind: Kind
    public let title: String
    public let message: String
    public let sessionID: String

    public init(kind: Kind, title: String, message: String, sessionID: String) {
        self.kind = kind
        self.title = title
        self.message = message
        self.sessionID = sessionID
    }
}

/// Turns changes between session snapshots into alerts. Each alert fires once.
public final class AlertEngine {
    private var previousStates: [String: SessionState]?   // nil until the first snapshot, so launch never alerts
    private var warned = Set<String>()
    private var coldAnnounced = Set<String>()

    public init() {}

    /// Alerts for sessions whose state just changed.
    public func alerts(forChangesIn sessions: [ClaudeSession]) -> [NotchAlert] {
        defer { previousStates = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { $1 }) }
        guard let previous = previousStates else { return [] }

        return sessions.compactMap { session in
            let before = previous[session.id]
            guard before != session.state else { return nil }
            switch session.state {
            case .needsYou:
                return NotchAlert(kind: .needsYou, title: session.title, message: session.detail, sessionID: session.id)
            case .done where before == .working:
                return NotchAlert(kind: .done, title: session.title, message: "Finished — your turn", sessionID: session.id)
            default:
                return nil
            }
        }
    }

    /// Alerts for prompt caches that are about to expire, or just did.
    public func alerts(forCachesIn sessions: [ClaudeSession], now: Date) -> [NotchAlert] {
        sessions.compactMap { session in
            guard session.state != .working, let cache = session.cache else { return nil }
            let remaining = cache.remaining(at: now)
            let key = "\(session.id)-\(Int(cache.expiresAt.timeIntervalSince1970))"   // one alert per cache generation

            if remaining <= 0, remaining > -30, coldAnnounced.insert(key).inserted {
                return NotchAlert(kind: .cacheCold, title: session.title,
                                  message: "Prompt cache went cold — next message re-reads context", sessionID: session.id)
            }
            if remaining > 0, remaining <= cache.warningThreshold, warned.insert(key).inserted {
                return NotchAlert(kind: .cacheLow, title: session.title,
                                  message: "Cache expires in \(Format.duration(remaining)) — send a message to keep it warm",
                                  sessionID: session.id)
            }
            return nil
        }
    }
}
