import Foundation
import Combine

/// Watches Claude Code's transcript folder and publishes the current list of sessions.
public final class SessionMonitor: ObservableObject {
    /// Most urgent first: needs you, working, done, idle; most recent first within each group.
    @Published public private(set) var sessions: [ClaudeSession] = []
    /// Ticks once a second so countdowns redraw.
    @Published public private(set) var now = Date()

    private let paths: Paths
    private let scanQueue = DispatchQueue(label: "claude-notch.scan", qos: .utility)
    private var scanTimer: Timer?
    private var clockTimer: Timer?
    private var scanInFlight = false   // main thread only

    public init(paths: Paths = .live) {
        self.paths = paths
    }

    /// A monitor frozen on the given sessions, never touching the disk (for documentation screenshots).
    public init(fixedSessions: [ClaudeSession], now: Date) {
        self.paths = .live
        self.sessions = fixedSessions
        self.now = now
    }

    public func start() {
        stop()
        refresh()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Config.pollInterval, repeats: true) { [weak self] _ in self?.refresh() }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
    }

    public func stop() {
        scanTimer?.invalidate()
        clockTimer?.invalidate()
    }

    public func refresh() {
        guard !scanInFlight else { return }   // a slow scan must not queue up behind itself
        scanInFlight = true
        scanQueue.async { [weak self] in
            guard let self else { return }
            let found = Self.scan(paths: self.paths, now: Date())
            DispatchQueue.main.async {
                self.scanInFlight = false
                if found != self.sessions { self.sessions = found }
            }
        }
    }

    /// One synchronous scan, for command-line diagnostics.
    public static func scanOnce(paths: Paths = .live) -> [ClaudeSession] {
        scan(paths: paths, now: Date())
    }

    /// Reads every recently modified transcript. Synchronous; callers decide which queue to run it on.
    static func scan(paths: Paths, now: Date) -> [ClaudeSession] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(at: paths.transcripts, includingPropertiesForKeys: nil) else { return [] }

        let loader = SessionLoader(paths: paths)
        let cutoff = now.addingTimeInterval(-Config.sessionWindow)
        var sessions: [ClaudeSession] = []

        for project in projects {
            let files = (try? fm.contentsOfDirectory(at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "jsonl" {
                guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      modified > cutoff,
                      let session = loader.load(transcript: file, fileModified: modified, now: now) else { continue }
                sessions.append(session)
            }
        }
        return sessions.sorted {
            $0.state.sortPriority != $1.state.sortPriority
                ? $0.state.sortPriority < $1.state.sortPriority
                : $0.lastActivity > $1.lastActivity
        }
    }
}
