import Foundation
import Combine

/// A local server (something listening on a TCP port) that a Claude session started.
public struct RunningServer: Equatable, Identifiable {
    public let pid: Int
    public let port: Int
    /// A short name for the program, such as `vite`.
    public let name: String
    public let sessionID: String
    public var id: String { "\(pid):\(port)" }

    public init(pid: Int, port: Int, name: String, sessionID: String) {
        self.pid = pid
        self.port = port
        self.name = name
        self.sessionID = sessionID
    }
}

/// Works out which session owns each listening process. Pure, so it can be tested without any real processes.
enum ServerAttribution {
    struct Process {
        let pid: Int
        let ppid: Int
        let command: String
    }

    struct LiveSession {
        let id: String
        let cwd: String
    }

    /// - Parameters:
    ///   - sessions: running Claude processes, by pid.
    ///   - listeners: listening process pid → ports.
    ///   - cwds: working folders of listening processes (only needed for the fallback below).
    /// A server belongs to the session whose `claude` process is its ancestor. Servers started by the desktop app's
    /// own preview feature have no such ancestor, so they are matched by working folder, but only when the Claude
    /// app launched them (a server you started yourself in a terminal is never claimed).
    static func attribute(processes: [Process], sessions: [Int: LiveSession], listeners: [Int: [Int]],
                          cwds: [Int: String]) -> [RunningServer] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })

        func ancestors(of pid: Int) -> [Process] {
            var chain: [Process] = []
            var seen: Set<Int> = [pid]
            var current = byPID[pid]?.ppid
            while let next = current, next > 1, !seen.contains(next), let process = byPID[next] {
                chain.append(process)
                seen.insert(next)
                current = process.ppid
            }
            return chain
        }

        var servers: [RunningServer] = []
        for (pid, ports) in listeners where sessions[pid] == nil {
            let chain = ancestors(of: pid)
            var owner = chain.lazy.compactMap { sessions[$0.pid] }.first
            if owner == nil, chain.contains(where: { $0.command.contains("/Claude.app/") }), let cwd = cwds[pid] {
                owner = sessions.values
                    .filter { cwd == $0.cwd || cwd.hasPrefix($0.cwd + "/") }
                    .max { $0.cwd.count < $1.cwd.count }
            }
            guard let owner else { continue }
            let name = label(for: byPID[pid]?.command ?? "")
            for port in ports { servers.append(RunningServer(pid: pid, port: port, name: name, sessionID: owner.id)) }
        }
        return servers.sorted { ($0.sessionID, $0.port) < ($1.sessionID, $1.port) }
    }

    /// `node /x/node_modules/.bin/vite --port 5173` → `vite`.
    static func label(for command: String) -> String {
        let launchers: Set<String> = ["node", "python", "python3", "ruby", "bun", "deno", "npm", "npx", "pnpm", "yarn"]
        let tokens = command.split(separator: " ").map(String.init)
        guard let first = tokens.first else { return "server" }
        let program = (first as NSString).lastPathComponent
        guard launchers.contains(program), let second = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return program }
        return (second as NSString).lastPathComponent
    }
}

/// Watches for servers that Claude sessions have left running, and publishes them by session id.
public final class ServerMonitor: ObservableObject {
    @Published public private(set) var servers: [String: [RunningServer]] = [:]

    private let paths: Paths
    private let queue = DispatchQueue(label: "claude-notch.servers", qos: .utility)
    private var timer: Timer?
    private var scanInFlight = false   // main thread only

    public init(paths: Paths = .live) {
        self.paths = paths
    }

    /// A monitor frozen on the given servers (for documentation screenshots).
    public init(fixed: [RunningServer]) {
        self.paths = .live
        self.servers = Dictionary(grouping: fixed, by: \.sessionID)
    }

    public func start() {
        stop()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Config.serverPollInterval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    public func stop() {
        timer?.invalidate()
    }

    private func refresh() {
        guard !scanInFlight else { return }
        scanInFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let found = Dictionary(grouping: Self.scan(paths: self.paths), by: \.sessionID)
            DispatchQueue.main.async {
                self.scanInFlight = false
                if found != self.servers { self.servers = found }
            }
        }
    }

    // MARK: Scanning

    /// One scan, for the `status` command.
    public static func scan(paths: Paths) -> [RunningServer] {
        let sessions = liveSessions(in: paths.claudeDir.appendingPathComponent("sessions"))
        guard !sessions.isEmpty,
              let ps = run("/bin/ps", ["-axo", "pid=,ppid=,command="]),
              let lsof = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]) else { return [] }

        let processes = parseProcesses(ps)
        let listeners = parseListeners(lsof)
        let cwds = workingFolders(of: Array(listeners.keys.filter { sessions[$0] == nil }))
        return ServerAttribution.attribute(processes: processes, sessions: sessions, listeners: listeners, cwds: cwds)
    }

    /// Claude Code writes `~/.claude/sessions/<pid>.json` for each running session.
    private static func liveSessions(in directory: URL) -> [Int: ServerAttribution.LiveSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var sessions: [Int: ServerAttribution.LiveSession] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = json["pid"] as? Int, let id = json["sessionId"] as? String,
                  kill(pid_t(pid), 0) == 0 else { continue }
            sessions[pid] = .init(id: id, cwd: json["cwd"] as? String ?? "")
        }
        return sessions
    }

    static func parseProcesses(_ output: String) -> [ServerAttribution.Process] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { return nil }
            return .init(pid: pid, ppid: ppid, command: String(parts[2]))
        }
    }

    /// `lsof -Fpn` prints `p<pid>` then one `n<address>:<port>` per socket.
    static func parseListeners(_ output: String) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        var pid: Int?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int(line.dropFirst()) }
            else if line.hasPrefix("n"), let pid, let port = line.split(separator: ":").last.flatMap({ Int($0) }) {
                if !(result[pid]?.contains(port) ?? false) { result[pid, default: []].append(port) }
            }
        }
        return result
    }

    private static func workingFolders(of pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty, let output = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", pids.map(String.init).joined(separator: ",")]) else { return [:] }
        var result: [Int: String] = [:]
        var pid: Int?
        for line in output.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int(line.dropFirst()) }
            else if line.hasPrefix("n"), let pid { result[pid] = String(line.dropFirst()) }
        }
        return result
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()   // read before waiting, or a full pipe deadlocks
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
