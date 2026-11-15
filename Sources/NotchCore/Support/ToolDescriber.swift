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

    /// How many lines of the command or change a card shows before it says "+N more".
    public static let maxDetailLines = 5
    private static let maxLineLength = 160

    /// The request broken down for the approval card: what it does, why, and the exact command or change.
    public static func detail(of tool: String, input: [String: Any]?) -> RequestDetail {
        let input = input ?? [:]
        func string(_ key: String) -> String? {
            guard let value = input[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        func file() -> String { string("file_path").map { ($0 as NSString).lastPathComponent } ?? "file" }
        func path() -> String? { string("file_path").map(abbreviatingHome) }

        switch tool {
        case "Bash":
            return RequestDetail(headline: "Run shell command", explanation: string("description"),
                                 lines: capped(plain: string("command") ?? ""))
        case "Edit":
            return RequestDetail(headline: "Edit \(file())", explanation: path(),
                                 lines: capped(removed: string("old_string") ?? "", added: string("new_string") ?? ""))
        case "MultiEdit":
            let edits = input["edits"] as? [[String: Any]] ?? []
            let first = edits.first
            let count = edits.count
            return RequestDetail(headline: "Edit \(file())" + (count > 1 ? " (\(count) changes)" : ""), explanation: path(),
                                 lines: capped(removed: first?["old_string"] as? String ?? "", added: first?["new_string"] as? String ?? ""))
        case "Write":
            let content = string("content") ?? ""
            let total = content.split(separator: "\n", omittingEmptySubsequences: false).count
            return RequestDetail(headline: "Write \(file())", explanation: [path(), "\(total) line\(total == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " · "),
                                 lines: capped(added: content))
        case "NotebookEdit":
            return RequestDetail(headline: "Edit notebook \(file())", explanation: (input["notebook_path"] as? String).map(abbreviatingHome),
                                 lines: capped(added: string("new_source") ?? ""))
        case "Read":
            return RequestDetail(headline: "Read \(file())", explanation: path(), lines: [])
        case "WebFetch":
            return RequestDetail(headline: "Fetch a web page", explanation: string("prompt"), lines: capped(plain: string("url") ?? ""))
        case "WebSearch":
            return RequestDetail(headline: "Search the web", lines: capped(plain: string("query") ?? ""))
        case "Grep", "Glob":
            return RequestDetail(headline: tool == "Grep" ? "Search file contents" : "Find files", explanation: string("path").map(abbreviatingHome),
                                 lines: capped(plain: string("pattern") ?? ""))
        default:
            let arguments = input.keys.sorted().map { key -> String in
                let value = input[key]
                let text = (value as? String) ?? (value.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }.map { String(decoding: $0, as: UTF8.self) } ?? "")
                return "\(key): \(text)"
            }
            return RequestDetail(headline: "Use \(displayName(of: tool))", lines: capped(plain: arguments.joined(separator: "\n")))
        }
    }

    static func abbreviatingHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private static func clip(_ line: Substring) -> String {
        line.count > maxLineLength ? String(line.prefix(maxLineLength)) + "…" : String(line)
    }

    private static func capped(plain text: String) -> [RequestDetail.Line] {
        cap(text.split(separator: "\n", omittingEmptySubsequences: false).map { .init(kind: .plain, text: clip($0)) })
    }

    private static func capped(added: String) -> [RequestDetail.Line] {
        cap(added.split(separator: "\n", omittingEmptySubsequences: false).map { .init(kind: .added, text: clip($0)) })
    }

    /// A removed block followed by an added one, sharing the line budget so both stay visible.
    private static func capped(removed: String, added: String) -> [RequestDetail.Line] {
        let old = removed.isEmpty ? [] : removed.split(separator: "\n", omittingEmptySubsequences: false)
        let new = added.isEmpty ? [] : added.split(separator: "\n", omittingEmptySubsequences: false)
        let budget = maxDetailLines
        let oldShown = new.isEmpty ? min(old.count, budget) : min(old.count, max(1, budget / 2))
        let newShown = min(new.count, budget - oldShown)
        var lines = old.prefix(oldShown).map { RequestDetail.Line(kind: .removed, text: clip($0)) }
        lines += new.prefix(newShown).map { RequestDetail.Line(kind: .added, text: clip($0)) }
        let hidden = (old.count - oldShown) + (new.count - newShown)
        if hidden > 0 { lines.append(.init(kind: .note, text: "+\(hidden) more line\(hidden == 1 ? "" : "s")")) }
        return lines
    }

    private static func cap(_ lines: [RequestDetail.Line]) -> [RequestDetail.Line] {
        guard lines.count > maxDetailLines else { return lines }
        let hidden = lines.count - (maxDetailLines - 1)
        return Array(lines.prefix(maxDetailLines - 1)) + [.init(kind: .note, text: "+\(hidden) more lines")]
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
