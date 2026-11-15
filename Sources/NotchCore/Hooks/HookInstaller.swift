import Foundation

/// Adds and removes this app's hooks in Claude Code's `settings.json`, and the scripts they run.
///
/// Safe by construction: it only ever touches entries whose command is one of our two scripts, keeps every other
/// setting and hook, refuses to modify a settings file it cannot parse, and keeps a one-time backup of the original.
public struct HookInstaller {
    public struct Report: Equatable {
        public let settingsFile: URL
        /// Set when a backup of the original settings file was made by this call.
        public let backupFile: URL?
        /// False when settings.json already had exactly what was asked for.
        public let changedSettings: Bool
    }

    public enum InstallError: LocalizedError {
        case settingsNotAJSONObject(URL)

        public var errorDescription: String? {
            switch self {
            case .settingsNotAJSONObject(let url):
                return "\(url.path) is not a valid JSON object. Fix or remove it, then run again. Nothing was changed."
            }
        }
    }

    /// Which hook events to subscribe to, and the script that handles each.
    private struct Subscription {
        let event: String
        let script: String
        let timeout: Int?
    }

    private static let subscriptions: [Subscription] = [
        .init(event: "Notification", script: HookScripts.recorderName, timeout: nil),
        .init(event: "Stop", script: HookScripts.recorderName, timeout: nil),
        .init(event: "UserPromptSubmit", script: HookScripts.recorderName, timeout: nil),
        .init(event: "PreToolUse", script: HookScripts.recorderName, timeout: nil),
        .init(event: "PostToolUse", script: HookScripts.recorderName, timeout: nil),
        .init(event: "SessionEnd", script: HookScripts.recorderName, timeout: nil),
        .init(event: "PermissionRequest", script: HookScripts.permissionName, timeout: Config.permissionHookTimeout),
    ]

    private let paths: Paths
    private let fm = FileManager.default

    public init(paths: Paths = .live) {
        self.paths = paths
    }

    // MARK: Install / uninstall

    @discardableResult
    public func install() throws -> Report {
        var settings = try readSettings()          // fail before writing anything if settings are unreadable
        try writeScripts()

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks = removingOurs(from: hooks)
        for sub in Self.subscriptions {
            var groups = hooks[sub.event] as? [[String: Any]] ?? []
            groups.append(["hooks": [hookEntry(for: sub)]])
            hooks[sub.event] = groups
        }
        settings["hooks"] = hooks
        return try writeSettings(settings)
    }

    @discardableResult
    public func uninstall() throws -> Report {
        var settings = try readSettings()
        let hooks = removingOurs(from: settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        let report = try writeSettings(settings)

        try? fm.removeItem(at: paths.installedHooks)
        return report
    }

    /// Names of the events currently wired to this app.
    public func installedEvents() -> [String] {
        guard let settings = try? readSettings(), let hooks = settings["hooks"] as? [String: Any] else { return [] }
        return hooks.filter { _, groups in (groups as? [[String: Any]])?.contains(where: Self.containsOurs) ?? false }.keys.sorted()
    }

    // MARK: Scripts

    private func writeScripts() throws {
        try fm.createDirectory(at: paths.installedHooks, withIntermediateDirectories: true)
        // Hook state files contain the commands Claude runs, so the data directory is private to the user.
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.notchDir.path)
        // Earlier versions kept the scripts directly in the notch directory.
        for legacy in [HookScripts.recorderName, HookScripts.permissionName] {
            try? fm.removeItem(at: paths.notchDir.appendingPathComponent(legacy))
        }
        for (name, body) in [(HookScripts.recorderName, HookScripts.recorder), (HookScripts.permissionName, HookScripts.permission)] {
            let file = paths.installedHooks.appendingPathComponent(name)
            try body.write(to: file, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
    }

    // MARK: settings.json

    private func hookEntry(for sub: Subscription) -> [String: Any] {
        let script = paths.installedHooks.appendingPathComponent(sub.script).path
        // Single-quoted so a home directory containing spaces still works.
        var entry: [String: Any] = ["type": "command", "command": "'\(script)' \(sub.event)"]
        if let timeout = sub.timeout { entry["timeout"] = timeout }
        return entry
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        let command = entry["command"] as? String ?? ""
        return command.contains(HookScripts.recorderName) || command.contains(HookScripts.permissionName)
    }

    private static func containsOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
    }

    /// The group without our entries, or nil if nothing of the user's is left in it.
    private static func strippingOurs(from group: [String: Any]) -> [String: Any]? {
        let entries = group["hooks"] as? [[String: Any]] ?? []
        let kept = entries.filter { !isOurs($0) }
        if kept.count == entries.count { return group }
        guard !kept.isEmpty else { return nil }
        var result = group
        result["hooks"] = kept
        return result
    }

    /// Returns `hooks` without any of our entries, dropping events left empty.
    private func removingOurs(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { result[event] = value; continue }
            let kept = groups.compactMap(Self.strippingOurs)
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    private func readSettings() throws -> [String: Any] {
        guard fm.fileExists(atPath: paths.settingsFile.path) else { return [:] }
        let data = try Data(contentsOf: paths.settingsFile)
        if data.allSatisfy({ $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\n") }) { return [:] }   // empty file
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.settingsNotAJSONObject(paths.settingsFile)
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws -> Report {
        let file = paths.settingsFile
        let original = try? readSettings()
        if let original, (original as NSDictionary).isEqual(to: settings) {
            return Report(settingsFile: file, backupFile: nil, changedSettings: false)
        }

        // Keep the first-ever version of the user's file, once.
        var backup: URL?
        let backupURL = file.appendingPathExtension("notch-backup")
        if fm.fileExists(atPath: file.path), !fm.fileExists(atPath: backupURL.path) {
            try fm.copyItem(at: file, to: backupURL)
            backup = backupURL
        }

        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: file, options: .atomic)
        return Report(settingsFile: file, backupFile: backup, changedSettings: true)
    }
}
