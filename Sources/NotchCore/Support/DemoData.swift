import Foundation

/// Made-up sessions and approvals, used to render the screenshots in the README without exposing anyone's real work.
public enum DemoData {
    public static func sessions(now: Date) -> [ClaudeSession] {
        func cache(_ seconds: TimeInterval, longLived: Bool = false) -> PromptCache {
            PromptCache(expiresAt: now.addingTimeInterval(seconds), isLongLived: longLived)
        }
        return [
            ClaudeSession(id: "demo-ci", title: "Fix flaky CI tests", project: "web-app", state: .needsYou,
                          detail: "Waiting to run Bash: npm test -- --runInBand", lastActivity: now.addingTimeInterval(-40),
                          cache: cache(250), context: ContextUsage(tokens: 148_000, window: 1_000_000), model: "Sonnet 5.5"),
            ClaudeSession(id: "demo-checkout", title: "Checkout flow refactor", project: "web-app", state: .working,
                          detail: "Edit CartSummary.swift", lastActivity: now.addingTimeInterval(-3),
                          cache: cache(300), context: ContextUsage(tokens: 720_000, window: 1_000_000), model: "Sonnet 5.5"),
            ClaudeSession(id: "demo-blog", title: "Write launch blog post", project: "marketing", state: .done,
                          detail: "Draft is ready, with three headline options at the top.", lastActivity: now.addingTimeInterval(-70),
                          cache: cache(2970, longLived: true), context: ContextUsage(tokens: 96_000, window: 1_000_000), model: "Opus 5.5"),
            ClaudeSession(id: "demo-export", title: "Data export script", project: "tools", state: .idle,
                          detail: "", lastActivity: now.addingTimeInterval(-2200),
                          cache: cache(1330, longLived: true), context: ContextUsage(tokens: 340_000, window: 1_000_000), model: "Sonnet 5.5"),
            ClaudeSession(id: "demo-copy", title: "Onboarding copy review", project: "docs", state: .idle,
                          detail: "", lastActivity: now.addingTimeInterval(-1100),
                          cache: cache(-800), context: ContextUsage(tokens: 61_000, window: 1_000_000), model: "Haiku 5.5"),
        ]
    }

    public static func approvals(now: Date) -> [PermissionRequest] {
        [
            PermissionRequest(id: "r1", sessionID: "demo-ci", toolName: "Bash",
                              summary: "npm test -- --runInBand --coverage", raisedAt: now.addingTimeInterval(-18)),
            PermissionRequest(id: "r2", sessionID: "demo-checkout", toolName: "Bash",
                              summary: "rm -rf dist .next && npm run build", raisedAt: now.addingTimeInterval(-6)),
        ]
    }
}
