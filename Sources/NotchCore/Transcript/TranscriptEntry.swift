import Foundation

/// Token counts reported on an assistant message.
struct TokenUsage: Equatable {
    var input = 0
    var cacheRead = 0
    var cacheCreation = 0
    var output = 0
    /// Of `cacheCreation`, how much was written with the 5-minute and 1-hour lifetimes.
    var created5m = 0
    var created1h = 0

    /// Everything sent for the request, plus the reply (including thinking), which becomes part of the next
    /// request's input. This matches what Claude Code's `/context` reports.
    var contextTokens: Int { input + cacheRead + cacheCreation + output }
    var wroteToCache: Bool { cacheCreation > 0 || created5m > 0 || created1h > 0 }

    init?(json: [String: Any]?) {
        guard let json else { return nil }
        input = json["input_tokens"] as? Int ?? 0
        cacheRead = json["cache_read_input_tokens"] as? Int ?? 0
        cacheCreation = json["cache_creation_input_tokens"] as? Int ?? 0
        output = json["output_tokens"] as? Int ?? 0
        let breakdown = json["cache_creation"] as? [String: Any]
        created5m = breakdown?["ephemeral_5m_input_tokens"] as? Int ?? 0
        created1h = breakdown?["ephemeral_1h_input_tokens"] as? Int ?? 0
    }
}

struct ContentBlock {
    let type: String?
    let text: String?
    let toolName: String?
    let toolInput: [String: Any]?

    init(_ json: [String: Any]) {
        type = json["type"] as? String
        text = json["text"] as? String
        toolName = json["name"] as? String
        toolInput = json["input"] as? [String: Any]
    }
}

/// One line of a Claude Code `.jsonl` transcript, with typed access to the fields this app reads.
struct TranscriptEntry {
    let raw: [String: Any]
    let timestamp: Date?

    init(_ raw: [String: Any]) {
        self.raw = raw
        self.timestamp = Self.parseDate(raw["timestamp"] as? String)
    }

    var type: String? { raw["type"] as? String }
    var isAssistant: Bool { type == "assistant" }
    var isUser: Bool { type == "user" }
    var uuid: String? { raw["uuid"] as? String }
    var parentUUID: String? { raw["parentUuid"] as? String }
    var cwd: String? { raw["cwd"] as? String }
    var customTitle: String? { raw["customTitle"] as? String }
    var aiTitle: String? { raw["aiTitle"] as? String }

    /// Subagent traffic, which doesn't describe the main conversation.
    var isSidechain: Bool { raw["isSidechain"] as? Bool ?? false }
    /// Injected by Claude Code rather than typed by the user.
    var isMeta: Bool { raw["isMeta"] as? Bool ?? false }
    var isCompactSummary: Bool { raw["isCompactSummary"] as? Bool ?? false }

    private var message: [String: Any]? { raw["message"] as? [String: Any] }
    var messageID: String? { message?["id"] as? String }
    var model: String? { message?["model"] as? String }
    var stopReason: String? { message?["stop_reason"] as? String }
    var usage: TokenUsage? { TokenUsage(json: message?["usage"] as? [String: Any]) }

    /// Plain-string content (typed prompts, command echoes), if the message has that shape.
    var contentString: String? { message?["content"] as? String }

    var blocks: [ContentBlock] {
        (message?["content"] as? [[String: Any]])?.map(ContentBlock.init) ?? []
    }

    /// All text in the message, whichever shape the content has.
    var allText: String {
        contentString ?? blocks.compactMap(\.text).joined()
    }

    /// A real prompt from the user, as opposed to a tool result.
    var isTypedPrompt: Bool {
        contentString != nil || blocks.contains { $0.type == "text" }
    }

    /// Housekeeping lines that are not turns for the model: slash-command echoes and their caveats.
    var isCommandEcho: Bool {
        guard let text = contentString else { return false }
        return text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") || text.hasPrefix("<command-message>")
    }

    // MARK: Dates

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return withFraction.date(from: string) ?? plain.date(from: string)
    }
}
