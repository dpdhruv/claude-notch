import XCTest
@testable import NotchCore

final class StateInferenceTests: XCTestCase {
    private let t0 = Fixture.t0

    private func infer(_ entry: [String: Any], idle: TimeInterval) -> StateInference.Outcome {
        StateInference.fromTranscript(lastTurn: TranscriptEntry(entry), idle: idle)
    }

    private func pendingTool(_ name: String, input: [String: Any] = ["command": "swift build"]) -> [String: Any] {
        Fixture.assistant(at: t0, blocks: [Fixture.toolUse(name, input: input)], stop: "tool_use")
    }

    // MARK: Pending tool calls

    func testFreshToolCallIsWorking() {
        let outcome = infer(pendingTool("Bash"), idle: 3)
        XCTAssertEqual(outcome.state, .working)
        XCTAssertEqual(outcome.detail, "Bash: swift build")
    }

    func testToolCallLeftPendingIsTakenToBeWaitingForApproval() {
        let outcome = infer(pendingTool("Bash"), idle: Config.approvalGuessDelay + 1)
        XCTAssertEqual(outcome.state, .needsYou)
        XCTAssertEqual(outcome.detail, "Waiting to run Bash: swift build")
    }

    func testAbandonedToolCallGoesIdle() {
        XCTAssertEqual(infer(pendingTool("Bash"), idle: Config.pendingToolStaleAfter + 1).state, .idle)
    }

    func testQuestionsAndPlansNeedYouImmediately() {
        XCTAssertEqual(infer(pendingTool("AskUserQuestion"), idle: 1), .init(state: .needsYou, detail: "Asking you a question"))
        XCTAssertEqual(infer(pendingTool("ExitPlanMode"), idle: 1), .init(state: .needsYou, detail: "Plan ready for your approval"))
    }

    // MARK: Replies

    func testFinishedReplyIsDoneThenIdle() {
        let reply = Fixture.assistant(at: t0, blocks: [Fixture.text("All set.\nSecond line")], stop: "end_turn")
        XCTAssertEqual(infer(reply, idle: 30), .init(state: .done, detail: "All set."))
        XCTAssertEqual(infer(reply, idle: Config.doneVisibleFor + 1).state, .idle)
    }

    func testReplyWithoutStopReasonIsStreamingThenFinished() {
        let reply = Fixture.assistant(at: t0, blocks: [Fixture.text("partial")], stop: nil)
        XCTAssertEqual(infer(reply, idle: 5), .init(state: .working, detail: "Thinking…"))
        XCTAssertEqual(infer(reply, idle: Config.unfinishedReplyDoneAfter + 1).state, .done)
    }

    // MARK: User turns

    func testToolResultMeansWorkingUntilItGoesQuiet() {
        XCTAssertEqual(infer(Fixture.toolResult(at: t0), idle: 10), .init(state: .working, detail: "Working…"))
        XCTAssertEqual(infer(Fixture.toolResult(at: t0), idle: Config.toolResultStaleAfter + 1).state, .idle)
    }

    func testInterruptedRequestIsIdle() {
        let interrupted = Fixture.user(at: t0, content: [["type": "text", "text": "[Request interrupted by user]"]])
        XCTAssertEqual(infer(interrupted, idle: 2), .init(state: .idle, detail: "Interrupted"))
    }

    // MARK: Hooks

    private func hook(_ event: String, at offset: TimeInterval, type: String? = nil, message: String? = nil) -> HookEvent {
        HookEvent(event: event, timestamp: t0.addingTimeInterval(offset), notificationType: type, message: message)
    }

    private func apply(_ hook: HookEvent?, to guess: StateInference.Outcome, idle: TimeInterval = 5, now: Date? = nil) -> StateInference.Outcome {
        StateInference.applying(hook, to: guess, idle: idle, lastTurnAt: t0, now: now ?? t0.addingTimeInterval(idle))
    }

    func testPermissionNotificationIsExactNeedsYou() {
        let outcome = apply(hook("Notification", at: 0.5, type: "permission_prompt", message: "Claude needs permission to use Bash"),
                            to: .init(state: .working, detail: "Bash: ls"))
        XCTAssertEqual(outcome, .init(state: .needsYou, detail: "Claude needs permission to use Bash"))
    }

    func testNotificationOlderThanTheTranscriptHasBeenAnswered() {
        let outcome = apply(hook("Notification", at: -10, type: "permission_prompt"), to: .init(state: .working, detail: "x"), idle: 5)
        XCTAssertEqual(outcome.state, .working)
    }

    func testIdlePromptIsNotNeedsYou() {
        XCTAssertEqual(apply(hook("Notification", at: 1, type: "idle_prompt"), to: .idle).state, .done)
    }

    func testStopMeansDone() {
        XCTAssertEqual(apply(hook("Stop", at: 1), to: .idle), .init(state: .done, detail: "Finished"))
    }

    func testToolHooksWithdrawTheApprovalGuess() {
        let guess = StateInference.Outcome(state: .needsYou, detail: "Waiting to run Bash")
        XCTAssertEqual(apply(hook("PreToolUse", at: 1), to: guess), .init(state: .working, detail: "Working…"))
    }

    func testOldToolHookNoLongerProvesWork() {
        let outcome = apply(hook("PostToolUse", at: 0), to: .init(state: .working, detail: "x"), idle: 700, now: t0.addingTimeInterval(700))
        XCTAssertEqual(outcome.state, .idle)
    }

    func testNoHookLeavesTheGuessAlone() {
        let guess = StateInference.Outcome(state: .done, detail: "x")
        XCTAssertEqual(apply(nil, to: guess), guess)
    }
}
