import Foundation
import XCTest
@testable import NotchCore

/// Builders for transcript lines and a throwaway home directory.
enum Fixture {
    /// A fixed "now" so every time-dependent rule is deterministic.
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func usage(input: Int = 10, cacheRead: Int = 0, cacheCreation: Int = 0, output: Int = 5,
                      created5m: Int = 0, created1h: Int = 0) -> [String: Any] {
        ["input_tokens": input, "cache_read_input_tokens": cacheRead, "cache_creation_input_tokens": cacheCreation,
         "output_tokens": output,
         "cache_creation": ["ephemeral_5m_input_tokens": created5m, "ephemeral_1h_input_tokens": created1h]]
    }

    static func text(_ string: String) -> [String: Any] { ["type": "text", "text": string] }

    static func toolUse(_ name: String, input: [String: Any] = [:]) -> [String: Any] {
        ["type": "tool_use", "id": "toolu_1", "name": name, "input": input]
    }

    static func assistant(uuid: String = UUID().uuidString, parent: String? = nil, messageID: String = UUID().uuidString,
                          at time: Date, blocks: [[String: Any]] = [text("ok")], stop: String? = "end_turn",
                          usage: [String: Any]? = nil, model: String = "claude-sonnet-5-5") -> [String: Any] {
        var message: [String: Any] = ["id": messageID, "role": "assistant", "model": model, "content": blocks]
        if let stop { message["stop_reason"] = stop }
        if let usage { message["usage"] = usage }
        var entry: [String: Any] = ["type": "assistant", "uuid": uuid, "timestamp": iso(time), "message": message, "cwd": "/Users/me/Projects/demo"]
        if let parent { entry["parentUuid"] = parent }
        return entry
    }

    static func user(uuid: String = UUID().uuidString, at time: Date, content: Any, extra: [String: Any] = [:]) -> [String: Any] {
        var entry: [String: Any] = ["type": "user", "uuid": uuid, "timestamp": iso(time), "message": ["role": "user", "content": content], "cwd": "/Users/me/Projects/demo"]
        extra.forEach { entry[$0.key] = $0.value }
        return entry
    }

    static func toolResult(at time: Date) -> [String: Any] {
        user(at: time, content: [["type": "tool_result", "tool_use_id": "toolu_1", "content": "done"]])
    }

    static func entries(_ dictionaries: [[String: Any]]) -> [TranscriptEntry] { dictionaries.map(TranscriptEntry.init) }

    static func jsonl(_ dictionaries: [[String: Any]]) -> Data {
        let lines = dictionaries.map { String(decoding: try! JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func session(id: String = "s1", state: SessionState = .idle, cache: PromptCache? = nil, title: String = "Demo") -> ClaudeSession {
        ClaudeSession(id: id, title: title, project: "demo", state: state, detail: "", lastActivity: t0, cache: cache,
                      context: ContextUsage(tokens: 1000, window: 1_000_000), model: "Sonnet 5.5")
    }
}

/// A scratch home directory, removed when the test ends.
class TempHomeTestCase: XCTestCase {
    var home: URL!
    var paths: Paths!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("claude-notch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        paths = Paths(home: home)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
