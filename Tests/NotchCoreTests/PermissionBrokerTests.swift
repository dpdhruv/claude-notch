import XCTest
@testable import NotchCore

final class PermissionBrokerTests: TempHomeTestCase {
    private func writeRequest(id: String, pid: Int32 = getpid(), tool: String = "Bash", input: [String: Any] = ["command": "swift build"]) throws {
        let request: [String: Any] = [
            "id": id, "pid": Int(pid), "ts": Fixture.t0.timeIntervalSince1970,
            "payload": ["session_id": "sess-1", "tool_name": tool, "tool_input": input],
        ]
        try write(try JSONSerialization.data(withJSONObject: request), to: paths.permissionRequests.appendingPathComponent("\(id).json"))
    }

    func testPicksUpRequestsFromTheHook() throws {
        try writeRequest(id: "r1")
        let broker = PermissionBroker(paths: paths)
        broker.poll()
        let request = try XCTUnwrap(broker.pending.first)
        XCTAssertEqual(request.id, "r1")
        XCTAssertEqual(request.sessionID, "sess-1")
        XCTAssertEqual(request.toolName, "Bash")
        XCTAssertEqual(request.summary, "swift build")
    }

    func testRequestsAreOrderedOldestFirst() throws {
        try writeRequest(id: "later")
        try writeRequest(id: "earlier")
        let laterURL = paths.permissionRequests.appendingPathComponent("later.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: laterURL)) as? [String: Any])
        json["ts"] = Fixture.t0.timeIntervalSince1970 + 10
        try JSONSerialization.data(withJSONObject: json).write(to: laterURL)

        let broker = PermissionBroker(paths: paths)
        broker.poll()
        XCTAssertEqual(broker.pending.map(\.id), ["earlier", "later"])
    }

    func testDropsRequestsWhoseHookProcessIsGone() throws {
        try writeRequest(id: "orphan", pid: 999_999)
        let broker = PermissionBroker(paths: paths)
        broker.poll()
        XCTAssertTrue(broker.pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.permissionRequests.appendingPathComponent("orphan.json").path))
    }

    func testAllowWritesTheDecisionAndClearsTheRequest() throws {
        try writeRequest(id: "r1")
        let broker = PermissionBroker(paths: paths)
        broker.poll()
        broker.respond(to: try XCTUnwrap(broker.pending.first), with: .allow)

        let response = try String(contentsOf: paths.permissionResponses.appendingPathComponent("r1.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        let decision = ((json["hookSpecificOutput"] as? [String: Any])?["decision"]) as? [String: Any]
        XCTAssertEqual(decision?["behavior"] as? String, "allow")
        XCTAssertTrue(broker.pending.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.permissionRequests.appendingPathComponent("r1.json").path))
    }

    func testDecisionPayloads() throws {
        func decision(_ d: PermissionDecision) throws -> [String: Any] {
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(d.hookOutput.utf8)) as? [String: Any])
            let output = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
            return try XCTUnwrap(output["decision"] as? [String: Any])
        }
        XCTAssertEqual(try decision(.allow)["behavior"] as? String, "allow")
        XCTAssertNil(try decision(.allow)["message"])
        XCTAssertEqual(try decision(.deny)["behavior"] as? String, "deny")
        XCTAssertNotNil(try decision(.deny)["message"])
        XCTAssertEqual(PermissionDecision.deferToApp.hookOutput, "PASS")
    }

    func testDeferringWritesThePassMarker() throws {
        try writeRequest(id: "r1")
        let broker = PermissionBroker(paths: paths)
        broker.poll()
        broker.respond(to: try XCTUnwrap(broker.pending.first), with: .deferToApp)
        XCTAssertEqual(try String(contentsOf: paths.permissionResponses.appendingPathComponent("r1.json")), "PASS")
    }

    func testHeartbeatExistsOnlyWhileRunning() {
        let broker = PermissionBroker(paths: paths)
        broker.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.heartbeat.path))
        broker.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.heartbeat.path))
    }
}

final class PermissionHookScriptTests: TempHomeTestCase {
    /// Runs the real shell script against a scratch data directory, as Claude Code would.
    private func runHook(payload: String, afterStart: (() -> Void)? = nil) throws -> String {
        try HookInstaller(paths: paths).install()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [paths.installedHooks.appendingPathComponent(HookScripts.permissionName).path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        afterStart?()
        process.waitUntilExit()
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private let bashPayload = #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"}}"#

    func testStaysSilentWhenTheAppIsNotRunning() throws {
        XCTAssertEqual(try runHook(payload: bashPayload), "")
    }

    func testNeverInterceptsQuestionsOrPlans() throws {
        let broker = PermissionBroker(paths: paths)
        broker.start()
        defer { broker.stop() }
        XCTAssertEqual(try runHook(payload: #"{"session_id":"s1","tool_name":"AskUserQuestion","tool_input":{}}"#), "")
    }

    func testRelaysTheAnswerGivenInTheNotch() throws {
        let broker = PermissionBroker(paths: paths)
        broker.start()
        defer { broker.stop() }

        let output = try runHook(payload: bashPayload) {
            // Act as the notch: wait for the request to appear, then answer it.
            let deadline = Date().addingTimeInterval(5)
            while broker.pending.isEmpty, Date() < deadline {
                broker.poll()
                Thread.sleep(forTimeInterval: 0.05)
            }
            if let request = broker.pending.first { broker.respond(to: request, with: .allow) }
        }
        XCTAssertTrue(output.contains(#""behavior":"allow""#), output)
    }

    func testDeferringProducesNoOutput() throws {
        let broker = PermissionBroker(paths: paths)
        broker.start()
        defer { broker.stop() }

        let output = try runHook(payload: bashPayload) {
            let deadline = Date().addingTimeInterval(5)
            while broker.pending.isEmpty, Date() < deadline {
                broker.poll()
                Thread.sleep(forTimeInterval: 0.05)
            }
            if let request = broker.pending.first { broker.respond(to: request, with: .deferToApp) }
        }
        XCTAssertEqual(output, "")
    }
}


final class RecorderHookScriptTests: TempHomeTestCase {
    private func record(_ event: String, payload: String) throws {
        try HookInstaller(paths: paths).install()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [paths.installedHooks.appendingPathComponent(HookScripts.recorderName).path, event]
        let input = Pipe()
        process.standardInput = input
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
    }

    private func stateFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: paths.hookStates.path)) ?? []).sorted()
    }

    func testRecordsTheEventUnderTheSessionId() throws {
        try record("Stop", payload: #"{"session_id":"abc-123","hook_event_name":"Stop"}"#)
        XCTAssertEqual(stateFiles(), ["abc-123.json"])
        let event = HookStateStore(paths: paths).latestEvent(forSession: "abc-123")
        XCTAssertEqual(event?.event, "Stop")
    }

    func testUsesTheFirstSessionIdNotOneQuotedInsideToolInput() throws {
        try record("PreToolUse", payload: #"{"session_id":"real","tool_input":{"command":"echo '\"session_id\":\"other\"'"}}"#)
        XCTAssertEqual(stateFiles(), ["real.json"])
    }

    func testRefusesSessionIdsThatCouldEscapeTheStateDirectory() throws {
        try record("Stop", payload: #"{"session_id":"../../escaped"}"#)
        XCTAssertEqual(stateFiles(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("escaped.json").path))
    }

    func testSessionEndRemovesTheState() throws {
        try record("Stop", payload: #"{"session_id":"gone"}"#)
        try record("SessionEnd", payload: #"{"session_id":"gone"}"#)
        XCTAssertEqual(stateFiles(), [])
    }
}
