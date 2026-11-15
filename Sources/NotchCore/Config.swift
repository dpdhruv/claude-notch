import Foundation

/// Every tunable number in one place, so behaviour can be adjusted without hunting through the code.
public enum Config {
    public static let version = "1.0.0"

    // MARK: Session discovery

    /// Only transcripts modified within this window are listed.
    public static let sessionWindow: TimeInterval = 12 * 3600
    /// How often transcripts are re-read.
    public static let pollInterval: TimeInterval = 1.5
    /// How often to look for servers left running by sessions (it runs `ps` and `lsof`, so not every tick).
    /// How long a stopping server gets before the notch offers to force-stop it.
    public static let forceStopAfter: TimeInterval = 3
    public static let serverPollInterval: TimeInterval = 5
    /// Bytes read from the end of a transcript, smallest first. Large transcripts can end in a long run of
    /// attachments and metadata, so the window is widened until a real message turns up.
    public static let transcriptTailSizes = [300_000, 3_000_000, 24_000_000]

    // MARK: State inference

    /// With no hook data, a tool call left pending this long is assumed to be waiting for approval.
    public static let approvalGuessDelay: TimeInterval = 8
    /// A reply with no stop reason is treated as finished after this much silence.
    public static let unfinishedReplyDoneAfter: TimeInterval = 20
    /// "Done" is shown for this long after the final reply, then the session reads as idle.
    public static let doneVisibleFor: TimeInterval = 120
    /// A reply still streaming with no new transcript line for this long is no longer "working".
    public static let thinkingStaleAfter: TimeInterval = 30
    /// A tool result with no follow-up for this long is no longer "working".
    public static let toolResultStaleAfter: TimeInterval = 300
    /// A pending tool call older than this is abandoned rather than "needs you".
    public static let pendingToolStaleAfter: TimeInterval = 3600
    /// A hook event this old no longer proves the session is working.
    public static let hookWorkingStaleAfter: TimeInterval = 600
    /// Tolerance when comparing hook timestamps with transcript timestamps.
    public static let hookClockSkew: TimeInterval = 1.5

    // MARK: Prompt cache

    public static let shortCacheLifetime: TimeInterval = 300
    public static let longCacheLifetime: TimeInterval = 3600
    /// Warn this long before a 5-minute / 1-hour cache expires.
    public static let shortCacheWarning: TimeInterval = 60
    public static let longCacheWarning: TimeInterval = 300
    /// The collapsed notch starts showing a countdown this long before expiry.
    public static let shortCacheCountdown: TimeInterval = 300
    public static let longCacheCountdown: TimeInterval = 900

    // MARK: Context window

    public static let standardContextWindow = 200_000
    public static let extendedContextWindow = 1_000_000

    // MARK: Quiet mode

    /// How long "Pause alerts" lasts.
    public static let pauseDuration: TimeInterval = 3600

    // MARK: Permission bridge

    /// How long the hook waits for an answer before handing the prompt back to Claude's own dialog.
    public static let permissionHandoff: TimeInterval = 110
    /// Timeout written into settings.json for the permission hook. Must exceed `permissionHandoff`.
    public static let permissionHookTimeout = 120
    /// How often the app refreshes its "I'm alive" marker, which the hook checks before intercepting a prompt.
    public static let heartbeatInterval: TimeInterval = 2
    /// The hook treats the app as gone when its heartbeat is older than this many seconds.
    public static let heartbeatMaxAge = 6
    public static let permissionPollInterval: TimeInterval = 0.3
    /// A request is dropped once its session shows activity this long after the request was raised.
    public static let answeredElsewhereSlack: TimeInterval = 3
}
