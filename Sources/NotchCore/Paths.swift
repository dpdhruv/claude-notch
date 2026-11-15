import Foundation

/// Every filesystem location the app touches. Injectable so tests can run against a temporary directory.
public struct Paths {
    public let home: URL
    /// Claude Code's config directory (`~/.claude`, or `$CLAUDE_CONFIG_DIR`).
    public let claudeDir: URL
    /// This app's own working directory (`~/.claude-notch`, or `$CLAUDE_NOTCH_HOME`).
    public let notchDir: URL

    public init(home: URL, claudeDir: URL? = nil, notchDir: URL? = nil) {
        self.home = home
        self.claudeDir = claudeDir ?? home.appendingPathComponent(".claude")
        self.notchDir = notchDir ?? home.appendingPathComponent(".claude-notch")
    }

    /// The real locations on this machine.
    public static let live: Paths = {
        let env = ProcessInfo.processInfo.environment
        func dir(_ key: String) -> URL? {
            env[key].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        }
        return Paths(home: FileManager.default.homeDirectoryForCurrentUser,
                     claudeDir: dir("CLAUDE_CONFIG_DIR"),
                     notchDir: dir("CLAUDE_NOTCH_HOME"))
    }()

    // MARK: Claude Code

    /// One folder per project, each holding one `<session-id>.jsonl` transcript per session.
    public var transcripts: URL { claudeDir.appendingPathComponent("projects") }
    public var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    /// Where the Claude desktop app keeps per-session metadata (used to map a transcript to its desktop session).
    public var desktopSessions: URL {
        home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }

    // MARK: This app

    public var installedHooks: URL { notchDir.appendingPathComponent("hooks") }
    public var hookStates: URL { notchDir.appendingPathComponent("state") }
    public var permissionRequests: URL { notchDir.appendingPathComponent("requests") }
    public var permissionResponses: URL { notchDir.appendingPathComponent("responses") }
    /// Touched regularly while the app runs; the permission hook only intercepts prompts while it is fresh.
    /// Held for as long as the app runs, so a second copy knows to quit.
    public var instanceLock: URL { notchDir.appendingPathComponent("app.lock") }
    /// Written by the app: whether the keyboard shortcuts registered.
    public var shortcutStatus: URL { notchDir.appendingPathComponent("shortcuts") }
    public var heartbeat: URL { notchDir.appendingPathComponent("alive") }
    public var installedBinary: URL { notchDir.appendingPathComponent("bin/ClaudeNotch") }
}
