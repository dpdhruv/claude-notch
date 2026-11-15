import Foundation

/// The facts about a session that can be read off the tail of its transcript, in one forward pass.
struct TranscriptSnapshot {
    private(set) var customTitle: String?
    private var firstAITitle: String?
    private(set) var cwd: String?
    /// Whether the session was started from the `claude` command line rather than the desktop app.
    private(set) var isTerminal = false

    /// The last real turn (typed prompt, tool result or assistant reply), ignoring housekeeping lines.
    private(set) var lastTurn: TranscriptEntry?
    private(set) var lastAssistant: TranscriptEntry?

    /// Set when `/compact` ran after the last assistant reply: an estimate of the summary's size in tokens.
    private(set) var compactedContextEstimate: Int?
    /// Lifetime of the most recent request that *wrote* to the cache. Read-only requests say nothing about it.
    private(set) var lastCacheWriteWasLongLived: Bool?

    private var timestampByUUID: [String: Date] = [:]
    /// API message id -> the entry that triggered it. A reply is logged as several entries sharing one message id.
    private var triggerByMessageID: [String: String] = [:]

    var title: String? { customTitle ?? firstAITitle }
    var projectName: String? { cwd.map { ($0 as NSString).lastPathComponent } }

    init(entries: [TranscriptEntry]) {
        for entry in entries {
            if let uuid = entry.uuid, let time = entry.timestamp { timestampByUUID[uuid] = time }
        }
        for entry in entries { fold(entry) }
    }

    private mutating func fold(_ entry: TranscriptEntry) {
        if let custom = entry.customTitle { customTitle = custom }
        if firstAITitle == nil, let ai = entry.aiTitle { firstAITitle = ai }
        guard !entry.isSidechain else { return }
        if let cwd = entry.cwd { self.cwd = cwd }
        if let entrypoint = entry.raw["entrypoint"] as? String { isTerminal = entrypoint == "cli" }

        if entry.isAssistant {
            lastAssistant = entry
            lastTurn = entry
            compactedContextEstimate = nil
            if let id = entry.messageID, triggerByMessageID[id] == nil, let parent = entry.parentUUID {
                triggerByMessageID[id] = parent
            }
            if let usage = entry.usage, usage.wroteToCache {
                // 1-hour entries come first in a prompt, so any 1-hour write means the bulk of the prefix lives an hour.
                lastCacheWriteWasLongLived = usage.created1h > 0
            }
        } else if entry.isUser {
            if entry.isCompactSummary {
                compactedContextEstimate = max(1000, entry.allText.count / 4)
            } else if !entry.isMeta && !entry.isCommandEcho {
                lastTurn = entry
            }
        }
    }

    // MARK: Derived

    /// When the prompt cache next goes cold. Measured from the *start* of the request that last used the cache,
    /// approximated by the entry that triggered the reply, because generation time counts against the lifetime.
    var promptCache: PromptCache? {
        guard let assistant = lastAssistant, let replyTime = assistant.timestamp else { return nil }
        var start = replyTime
        if let id = assistant.messageID, let trigger = triggerByMessageID[id],
           let triggerTime = timestampByUUID[trigger], triggerTime <= replyTime {
            start = triggerTime
        }
        let longLived = lastCacheWriteWasLongLived ?? false
        return PromptCache(expiresAt: start.addingTimeInterval(longLived ? Config.longCacheLifetime : Config.shortCacheLifetime),
                           isLongLived: longLived)
    }

    /// Context usage as of the last assistant reply, or an estimate right after `/compact`.
    var contextUsage: ContextUsage {
        let model = lastAssistant?.model ?? ""
        if let estimate = compactedContextEstimate {
            return ContextUsage(tokens: estimate, window: ModelCatalog.contextWindow(for: model, observedTokens: estimate), isEstimate: true)
        }
        let tokens = lastAssistant?.usage?.contextTokens ?? 0
        return ContextUsage(tokens: tokens, window: ModelCatalog.contextWindow(for: model, observedTokens: tokens))
    }
}
