import XCTest
@testable import NotchCore

final class ServerAttributionTests: XCTestCase {
    private typealias P = ServerAttribution.Process
    private let claude = ServerAttribution.LiveSession(id: "s1", cwd: "/work/app")

    func testServerStartedBySessionBelongsToIt() {
        let processes = [P(pid: 10, ppid: 1, command: "claude"), P(pid: 11, ppid: 10, command: "/bin/zsh -c npm run dev"),
                         P(pid: 12, ppid: 11, command: "node /work/app/node_modules/.bin/vite --port 5173")]
        let found = ServerAttribution.attribute(processes: processes, sessions: [10: claude], listeners: [12: [5173]], cwds: [:])
        XCTAssertEqual(found, [RunningServer(pid: 12, port: 5173, name: "vite", sessionID: "s1")])
    }

    func testSessionsOwnListeningPortIsNotAServer() {
        let found = ServerAttribution.attribute(processes: [P(pid: 10, ppid: 1, command: "claude")], sessions: [10: claude], listeners: [10: [63392]], cwds: [:])
        XCTAssertTrue(found.isEmpty)
    }

    func testServersFromOutsideClaudeAreNotClaimed() {
        let processes = [P(pid: 10, ppid: 1, command: "claude"), P(pid: 20, ppid: 1, command: "postgres"),
                         P(pid: 30, ppid: 29, command: "node server.js"), P(pid: 29, ppid: 1, command: "-zsh")]
        let found = ServerAttribution.attribute(processes: processes, sessions: [10: claude], listeners: [20: [5432], 30: [8080]], cwds: [30: "/work/app"])
        XCTAssertTrue(found.isEmpty, "a server you started in your own terminal stays yours, even in the same folder")
    }

    func testDesktopPreviewServersMatchByFolder() {
        let processes = [P(pid: 5, ppid: 1, command: "/Applications/Claude.app/Contents/MacOS/Claude"),
                         P(pid: 6, ppid: 5, command: "/Applications/Claude.app/Contents/Helpers/disclaimer -- npm run dev"),
                         P(pid: 7, ppid: 6, command: "node /work/app/node_modules/.bin/vite")]
        let found = ServerAttribution.attribute(processes: processes, sessions: [10: claude], listeners: [7: [5173]], cwds: [7: "/work/app/web"])
        XCTAssertEqual(found.map(\.sessionID), ["s1"])
    }

    func testLabels() {
        XCTAssertEqual(ServerAttribution.label(for: "node /a/b/.bin/vite --port 1"), "vite")
        XCTAssertEqual(ServerAttribution.label(for: "python3 -m http.server 8000"), "http.server")
        XCTAssertEqual(ServerAttribution.label(for: "/usr/bin/postgres -D x"), "postgres")
    }

    func testParsesLsofAndPsOutput() {
        XCTAssertEqual(ServerMonitor.parseListeners("p12\nn127.0.0.1:5173\nn[::1]:5173\np13\nn*:5000\n"), [12: [5173], 13: [5000]])
        let processes = ServerMonitor.parseProcesses("  12   1 /bin/zsh -c x\n 13 12 node a b\n")
        XCTAssertEqual(processes.map(\.pid), [12, 13])
        XCTAssertEqual(processes[1].command, "node a b")
    }
}
