import Foundation

/// A tool-permission prompt that Claude Code handed to the notch.
public struct PermissionRequest: Identifiable, Equatable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    /// The command, file path or URL the tool wants to act on, ready to display.
    public let summary: String
    public let raisedAt: Date
}

public enum PermissionDecision: Equatable {
    case allow
    case deny
    /// Print nothing, so Claude Code shows its own dialog instead.
    case deferToApp

    /// The text the permission hook script relays to Claude Code (`PASS` means "say nothing").
    var hookOutput: String {
        let behavior: String
        switch self {
        case .deferToApp: return "PASS"
        case .allow: behavior = "allow"
        case .deny: behavior = "deny"
        }
        var decision: [String: Any] = ["behavior": behavior]
        if self == .deny { decision["message"] = "Denied from Claude Notch" }
        let payload: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return "PASS" }
        return String(decoding: data, as: UTF8.self)
    }
}
