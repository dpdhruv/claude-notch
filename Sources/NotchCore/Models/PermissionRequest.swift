import Foundation

/// A tool-permission prompt that Claude Code handed to the notch.
public struct PermissionRequest: Identifiable, Equatable {
    public let id: String
    public let sessionID: String
    public let toolName: String
    /// The command, file path or URL the tool wants to act on, ready to display.
    public let summary: String
    /// What the tool will do, broken down for display: a headline, Claude's own explanation and the exact change.
    public let detail: RequestDetail
    /// The folder the session is working in.
    public let directory: String?
    public let raisedAt: Date

    public init(id: String, sessionID: String, toolName: String, summary: String,
                detail: RequestDetail? = nil, directory: String? = nil, raisedAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.toolName = toolName
        self.summary = summary
        self.detail = detail ?? RequestDetail(headline: ToolDescriber.displayName(of: toolName),
                                              lines: summary.isEmpty ? [] : [.init(kind: .plain, text: summary)])
        self.directory = directory
        self.raisedAt = raisedAt
    }
}

/// A permission request, laid out for a person to judge.
public struct RequestDetail: Equatable {
    public struct Line: Equatable {
        public enum Kind: Equatable { case plain, added, removed, note }
        public let kind: Kind
        public let text: String
        public init(kind: Kind, text: String) { self.kind = kind; self.text = text }
    }

    /// What is about to happen, e.g. "Run command" or "Edit NotchPanel.swift".
    public let headline: String
    /// Claude's own explanation (the Bash tool's `description`, a fetch prompt…), if it gave one.
    public let explanation: String?
    /// The file or folder involved, when there is one.
    public let location: String?
    /// The exact command, file change or arguments, capped so the card stays compact.
    public let lines: [Line]

    /// What to lead the card with: Claude's own words when it gave any, otherwise the headline.
    public var title: String { explanation ?? headline }

    public init(headline: String, explanation: String? = nil, location: String? = nil, lines: [Line]) {
        self.headline = headline
        self.explanation = explanation
        self.location = location
        self.lines = lines
    }
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
