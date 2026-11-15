import XCTest
@testable import NotchCore

final class HookInstallerTests: TempHomeTestCase {
    private var installer: HookInstaller { HookInstaller(paths: paths) }

    private func settings() throws -> [String: Any] {
        let data = try Data(contentsOf: paths.settingsFile)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func groups(_ event: String) throws -> [[String: Any]] {
        let hooks = try XCTUnwrap(settings()["hooks"] as? [String: Any])
        return try XCTUnwrap(hooks[event] as? [[String: Any]])
    }

    private func commands(_ event: String) throws -> [String] {
        try groups(event).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private let userStopHook: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]

    private func writeSettings(_ object: [String: Any]) throws {
        try write(try JSONSerialization.data(withJSONObject: object), to: paths.settingsFile)
    }

    func testInstallsIntoAMissingSettingsFile() throws {
        let report = try installer.install()
        XCTAssertTrue(report.changedSettings)
        XCTAssertNil(report.backupFile, "nothing to back up")
        XCTAssertEqual(installer.installedEvents(), ["Notification", "PermissionRequest", "PostToolUse", "PreToolUse", "SessionEnd", "Stop", "UserPromptSubmit"])
    }

    func testWritesExecutableScripts() throws {
        try installer.install()
        for name in [HookScripts.recorderName, HookScripts.permissionName] {
            let path = paths.installedHooks.appendingPathComponent(name).path
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: path), name)
        }
    }

    func testCommandsAreQuotedAndNameTheirEvent() throws {
        try installer.install()
        let command = try XCTUnwrap(commands("Stop").first)
        XCTAssertTrue(command.hasPrefix("'"), "paths with spaces must survive the shell")
        XCTAssertTrue(command.hasSuffix(" Stop"))
        XCTAssertTrue(command.contains(HookScripts.recorderName))
    }

    func testPermissionHookGetsALongerTimeoutThanItsOwnWait() throws {
        try installer.install()
        let entry = try XCTUnwrap((groups("PermissionRequest").first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(entry["timeout"] as? Int, Config.permissionHookTimeout)
        XCTAssertGreaterThan(Double(Config.permissionHookTimeout), Config.permissionHandoff)
    }

    func testKeepsEverythingElseInSettings() throws {
        try writeSettings(["model": "opus", "permissions": ["allow": ["Bash(ls)"]], "hooks": ["Stop": [userStopHook]]])
        try installer.install()

        let s = try settings()
        XCTAssertEqual(s["model"] as? String, "opus")
        XCTAssertNotNil(s["permissions"])
        XCTAssertEqual(try commands("Stop").count, 2)
        XCTAssertTrue(try commands("Stop").contains("echo mine"))
    }

    func testInstallingTwiceChangesNothing() throws {
        try installer.install()
        let first = try settings()
        let report = try installer.install()
        XCTAssertFalse(report.changedSettings)
        XCTAssertTrue((first as NSDictionary).isEqual(to: try settings()))
        XCTAssertEqual(try groups("Stop").count, 1, "no duplicates")
    }

    func testBacksUpTheOriginalOnceOnly() throws {
        try writeSettings(["model": "opus"])
        let first = try installer.install()
        let backup = try XCTUnwrap(first.backupFile)
        let original = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any]
        XCTAssertEqual(original?["model"] as? String, "opus")
        XCTAssertNil(original?["hooks"])

        try writeSettings(["model": "sonnet"])
        XCTAssertNil(try installer.install().backupFile, "the first backup is the valuable one")
        let stillOriginal = try JSONSerialization.jsonObject(with: Data(contentsOf: backup)) as? [String: Any]
        XCTAssertEqual(stillOriginal?["model"] as? String, "opus")
    }

    func testUninstallRemovesOnlyOurHooks() throws {
        try writeSettings(["model": "opus", "hooks": ["Stop": [userStopHook]]])
        try installer.install()
        try installer.uninstall()

        XCTAssertEqual(try commands("Stop"), ["echo mine"])
        XCTAssertEqual(installer.installedEvents(), [])
        let hooks = try XCTUnwrap(settings()["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["Stop"], "events we added are removed entirely")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installedHooks.path))
    }

    func testKeepsUserHooksThatShareAGroupWithOurs() throws {
        let shared: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"],
                                               ["type": "command", "command": "'/x/.claude-notch/hooks/notch-hook.sh' Stop"]]]
        try writeSettings(["hooks": ["Stop": [shared]]])
        try installer.install()
        XCTAssertTrue(try commands("Stop").contains("echo mine"), "reinstalling must not delete the user's hook")
        try installer.uninstall()
        XCTAssertEqual(try commands("Stop"), ["echo mine"])
    }

    func testUninstallDropsTheHooksKeyWhenNothingIsLeft() throws {
        try writeSettings(["model": "opus"])
        try installer.install()
        try installer.uninstall()
        let s = try settings()
        XCTAssertNil(s["hooks"])
        XCTAssertEqual(s["model"] as? String, "opus")
    }

    func testUninstallWithoutInstallIsHarmless() throws {
        let report = try installer.uninstall()
        XCTAssertFalse(report.changedSettings)
    }

    func testRefusesToTouchSettingsItCannotParse() throws {
        try write(Data("{ not json".utf8), to: paths.settingsFile)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertTrue(error is HookInstaller.InstallError)
        }
        XCTAssertEqual(try String(contentsOf: paths.settingsFile), "{ not json", "the file must be left exactly as it was")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.installedHooks.path), "nothing is written when settings are unreadable")
    }

    func testEmptySettingsFileIsTreatedAsEmpty() throws {
        try write(Data(), to: paths.settingsFile)
        XCTAssertNoThrow(try installer.install())
    }

    func testOldStyleHookEntriesAreReplaced() throws {
        // Earlier versions registered the scripts straight from ~/.claude-notch.
        let old: [String: Any] = ["hooks": [["type": "command", "command": "/Users/me/.claude-notch/notch-hook.sh Stop"]]]
        try writeSettings(["hooks": ["Stop": [old]]])
        try installer.install()
        XCTAssertEqual(try commands("Stop").count, 1)
        XCTAssertTrue(try commands("Stop")[0].contains("/hooks/"))
    }
}
