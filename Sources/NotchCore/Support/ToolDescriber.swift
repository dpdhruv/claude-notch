import Foundation

/// Turns raw tool calls into short human-readable text, icons and risk flags.
public enum ToolDescriber {
    /// Tools that need the full Claude UI (a question or a plan), so approval is never routed through the notch.
    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// One-line status such as `Bash: swift build` or `Edit main.swift`.
    static func activity(of tool: String, input: [String: Any]?) -> String {
        if let command = input?["command"] as? String { return "\(tool): " + command.prefix(48) }
        if let path = input?["file_path"] as? String { return "\(tool) \((path as NSString).lastPathComponent)" }
        if let pattern = input?["pattern"] as? String { return "\(tool) \(pattern.prefix(40))" }
        return displayName(of: tool)
    }

    /// The thing a permission request is about: the command, the file, the URL…
    public static func summary(of tool: String, input: [String: Any]?) -> String {
        guard let input else { return "" }
        if let command = input["command"] as? String { return command }
        if let path = input["file_path"] as? String {
            let body = (input["new_string"] as? String) ?? (input["content"] as? String) ?? ""
            return body.isEmpty ? path : path + "\n" + body.prefix(240)
        }
        if let url = input["url"] as? String { return url }
        if let pattern = input["pattern"] as? String { return pattern }
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return String(json.prefix(300))
    }

    public static func displayName(of tool: String) -> String {
        tool.replacingOccurrences(of: "mcp__", with: "")
    }

    /// SF Symbol name.
    public static func icon(for tool: String) -> String {
        switch tool {
        case "Bash": return "terminal"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "doc.text"
        case "Read": return "eye"
        case "WebFetch", "WebSearch": return "globe"
        case "Grep", "Glob": return "magnifyingglass"
        default: return tool.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }

    private static let riskyPatterns: [(needle: String, label: String)] = [
        ("rm -rf", "Deletes files"), ("rm -fr", "Deletes files"),
        ("sudo ", "Uses sudo"),
        ("git push --force", "Force push"), ("git push -f", "Force push"),
        ("git reset --hard", "Discards changes"),
        ("| sh", "Runs download"), ("| bash", "Runs download"),
        ("chmod 777", "Open perms"), ("mkfs", "Formats disk"), ("dd if=", "Raw disk write"),
        ("drop table", "Drops data"), ("> /dev/", "Writes device"),
    ]

    /// A cheap heuristic flag for shell commands that deserve a second look. Not a security boundary.
    public static func risk(tool: String, summary: String) -> String? {
        guard tool == "Bash" else { return nil }
        let text = summary.lowercased()
        return riskyPatterns.first { text.contains($0.needle) }?.label
    }
}
