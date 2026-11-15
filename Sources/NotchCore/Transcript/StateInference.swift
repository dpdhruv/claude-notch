import Foundation

/// Decides what a session is doing from the last real turn in its transcript, then refines it with hook data.
/// Pure functions of their inputs (including the clock), so every rule is unit-tested.
enum StateInference {
    struct Outcome: Equatable {
        var state: SessionState
        var detail: String

        static let idle = Outcome(state: .idle, detail: "")
    }

    // MARK: From the transcript alone

    /// - Parameter idle: seconds since the last real message.
    static func fromTranscript(lastTurn: TranscriptEntry, idle: TimeInterval) -> Outcome {
        if lastTurn.isAssistant { return fromAssistantReply(lastTurn, idle: idle) }
        if lastTurn.isUser { return fromUserTurn(lastTurn, idle: idle) }
        return .idle
    }

    private static func fromAssistantReply(_ reply: TranscriptEntry, idle: TimeInterval) -> Outcome {
        if let call = reply.blocks.last(where: { $0.type == "tool_use" }) {
            return fromPendingToolCall(name: call.toolName ?? "tool", input: call.toolInput, idle: idle)
        }

        let finished = reply.stopReason == "end_turn" || reply.stopReason == "stop_sequence"
            || (reply.stopReason == nil && idle > Config.unfinishedReplyDoneAfter)
        if finished {
            let lastWords = reply.blocks.last(where: { $0.type == "text" })?.text.flatMap(firstLine)
            return Outcome(state: idle < Config.doneVisibleFor ? .done : .idle, detail: lastWords ?? "Finished")
        }
        return idle < Config.thinkingStaleAfter ? Outcome(state: .working, detail: "Thinking…") : .idle
    }

    /// The last thing Claude did was call a tool and nothing has come back yet: it is either running or waiting on you.
    private static func fromPendingToolCall(name: String, input: [String: Any]?, idle: TimeInterval) -> Outcome {
        if ToolDescriber.interactiveTools.contains(name) {
            guard idle < Config.pendingToolStaleAfter else { return .idle }
            return Outcome(state: .needsYou, detail: name == "ExitPlanMode" ? "Plan ready for your approval" : "Asking you a question")
        }
        let activity = ToolDescriber.activity(of: name, input: input)
        if idle <= Config.approvalGuessDelay { return Outcome(state: .working, detail: activity) }
        if idle < Config.pendingToolStaleAfter { return Outcome(state: .needsYou, detail: "Waiting to run \(activity)") }
        return .idle
    }

    private static func fromUserTurn(_ turn: TranscriptEntry, idle: TimeInterval) -> Outcome {
        if turn.allText.hasPrefix("[Request interrupted") { return Outcome(state: .idle, detail: "Interrupted") }
        return idle < Config.toolResultStaleAfter ? Outcome(state: .working, detail: "Working…") : .idle
    }

    // MARK: Refined by hooks

    /// Hook events are authoritative when present: they fire at the exact moment Claude asks for input,
    /// instead of leaving the app to guess from silence.
    static func applying(_ hook: HookEvent?, to guess: Outcome, idle: TimeInterval, lastTurnAt: Date, now: Date) -> Outcome {
        guard let hook else { return guess }
        var outcome = guess
        switch hook.event {
        case "Notification":
            if hook.notificationType == "idle_prompt" {
                outcome = Outcome(state: idle < Config.doneVisibleFor ? .done : .idle, detail: guess.detail)
            } else if hook.timestamp >= lastTurnAt.addingTimeInterval(-Config.hookClockSkew) {
                outcome = Outcome(state: .needsYou, detail: hook.message ?? "Needs your input")
            } else {
                // The transcript moved on after the prompt was raised, so it has been answered.
                outcome = Outcome(state: idle < Config.thinkingStaleAfter ? .working : .idle, detail: guess.detail)
            }
        case "Stop":
            outcome.state = idle < Config.doneVisibleFor ? .done : .idle
            if outcome.detail.isEmpty { outcome.detail = "Finished" }
        case "UserPromptSubmit", "PreToolUse", "PostToolUse":
            // Hooks say work is happening, so the "pending tool means waiting for you" guess is withdrawn.
            if outcome.state == .needsYou { outcome = Outcome(state: .working, detail: "Working…") }
            if now.timeIntervalSince(hook.timestamp) > Config.hookWorkingStaleAfter { outcome.state = .idle }
        default:
            break
        }
        return outcome
    }

    private static func firstLine(_ text: String) -> String? {
        guard let line = text.split(separator: "\n").first, !line.isEmpty else { return nil }
        return String(line.prefix(90))
    }
}
