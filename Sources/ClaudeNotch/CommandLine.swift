import AppKit
import Foundation
import NotchCore

/// `ClaudeNotch <command>`: housekeeping commands that run and exit, without starting the app.
enum CommandLineTool {
    static let usage = """
    ClaudeNotch \(Config.version): live Claude session status in the MacBook notch.

    Usage: ClaudeNotch [command]

      (no command)      run the app
      install-hooks     add the notch's hooks to Claude Code's settings.json
      uninstall-hooks   remove them again (everything else in settings.json is left alone)
      status            show what is installed and what the app can see
      render-screenshots <folder>   write the README screenshots from demo data (no screen capture)
      --version, --help

    Environment:
      CLAUDE_CONFIG_DIR     Claude Code's config directory (default ~/.claude)
      CLAUDE_NOTCH_HOME     this app's data directory (default ~/.claude-notch)
      CLAUDE_NOTCH_EXPANDED start with the session list open (handy for screenshots)
    """

    /// Runs a command-line action if `arguments` names one. Returns the exit code, or nil to run the app.
    static func run(arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "install-hooks": return installHooks()
        case "uninstall-hooks": return uninstallHooks()
        case "status": return status()
        case "render-screenshots": return renderScreenshots(into: arguments.dropFirst().first ?? "docs/images")
        case "--version", "-v": print("ClaudeNotch \(Config.version)"); return 0
        case "--help", "-h", "help": print(usage); return 0
        default:
            FileHandle.standardError.write(Data("Unknown command '\(command)'.\n\n\(usage)\n".utf8))
            return 64
        }
    }

    private static func installHooks() -> Int32 {
        do {
            let report = try HookInstaller().install()
            print(report.changedSettings ? "Hooks installed in \(report.settingsFile.path)" : "Hooks already installed in \(report.settingsFile.path)")
            if let backup = report.backupFile { print("Backup of your original settings: \(backup.path)") }
            print("Restart any running Claude sessions so they pick the hooks up.")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Could not install hooks: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func uninstallHooks() -> Int32 {
        do {
            let report = try HookInstaller().uninstall()
            print(report.changedSettings ? "Hooks removed from \(report.settingsFile.path)" : "No notch hooks were installed.")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Could not remove hooks: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private static func renderScreenshots(into folder: String) -> Int32 {
        _ = NSApplication.shared   // AppKit must be initialised before SwiftUI can render
        do {
            try MainActor.assumeIsolated { try ScreenshotRenderer.render(to: URL(fileURLWithPath: folder)) }
            return 0
        } catch {
            FileHandle.standardError.write(Data("Could not render screenshots: \(error)\n".utf8))
            return 1
        }
    }

    private static func status() -> Int32 {
        let paths = Paths.live
        let fm = FileManager.default
        let events = HookInstaller().installedEvents()
        let heartbeatAge = (try? fm.attributesOfItem(atPath: paths.heartbeat.path)[.modificationDate] as? Date)?.flatMap { Date().timeIntervalSince($0) }
        let sessions = SessionMonitor.scanOnce(paths: paths)

        print("""
        ClaudeNotch \(Config.version)
          Claude config      \(paths.claudeDir.path)
          Transcripts        \(fm.fileExists(atPath: paths.transcripts.path) ? "found" : "NOT FOUND") (\(sessions.count) recent session\(sessions.count == 1 ? "" : "s"))
          Hooks              \(events.isEmpty ? "not installed (run: ClaudeNotch install-hooks)" : "installed for \(events.joined(separator: ", "))")
          App                \(heartbeatAge.map { $0 < 6 ? "running" : "not running" } ?? "not running")
          Data directory     \(paths.notchDir.path)
        """)
        return 0
    }
}
