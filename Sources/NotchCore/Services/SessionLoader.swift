import Foundation

/// Builds a `ClaudeSession` from one transcript file. Stateless apart from the clock passed in, so it is easy to test.
struct SessionLoader {
    let paths: Paths

    func load(transcript url: URL, fileModified: Date, now: Date) -> ClaudeSession? {
        let id = url.deletingPathExtension().lastPathComponent
        var lastSnapshot: TranscriptSnapshot?

        for bytes in Config.transcriptTailSizes {
            let tail = TranscriptReader.readTail(of: url, bytes: bytes)
            // An empty window means the last line alone exceeds it (a big attachment): widen unless this was the whole file.
            if tail.entries.isEmpty {
                if tail.coversWholeFile { return nil }
                continue
            }
            let snapshot = TranscriptSnapshot(entries: tail.entries)
            if snapshot.lastTurn != nil { return session(id: id, snapshot: snapshot, fileModified: fileModified, now: now) }
            lastSnapshot = snapshot
            if tail.coversWholeFile { break }
        }
        // Nothing but metadata, even in the widest window: still list the session, as idle.
        return lastSnapshot.map { placeholder(id: id, snapshot: $0, fileModified: fileModified) }
    }

    private func session(id: String, snapshot: TranscriptSnapshot, fileModified: Date, now: Date) -> ClaudeSession? {
        guard let lastTurn = snapshot.lastTurn else { return nil }

        // The file's modification time is bumped by metadata lines (titles, modes…), so trust the last message's own time.
        let lastActivity = min(fileModified, lastTurn.timestamp ?? fileModified)
        let idle = now.timeIntervalSince(lastActivity)

        let guess = StateInference.fromTranscript(lastTurn: lastTurn, idle: idle)
        let hook = HookStateStore(paths: paths).latestEvent(forSession: id)
        let outcome = StateInference.applying(hook, to: guess, idle: idle, lastTurnAt: lastActivity, now: now)

        let project = snapshot.projectName ?? "session"
        return ClaudeSession(
            id: id,
            title: snapshot.title ?? project,
            project: project,
            state: outcome.state,
            detail: outcome.detail,
            lastActivity: lastActivity,
            cache: snapshot.promptCache,
            context: snapshot.contextUsage,
            model: ModelCatalog.displayName(for: snapshot.lastAssistant?.model ?? ""))
    }

    private func placeholder(id: String, snapshot: TranscriptSnapshot, fileModified: Date) -> ClaudeSession {
        let project = snapshot.projectName ?? "session"
        return ClaudeSession(
            id: id, title: snapshot.title ?? project, project: project, state: .idle, detail: "",
            lastActivity: fileModified, cache: nil,
            context: ContextUsage(tokens: snapshot.compactedContextEstimate ?? 0,
                                  window: Config.standardContextWindow,
                                  isEstimate: snapshot.compactedContextEstimate != nil),
            model: "")
    }
}
