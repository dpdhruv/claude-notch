import Foundation

/// Finds the way back into a session from its transcript id.
public struct SessionLinker {
    private let paths: Paths

    public init(paths: Paths = .live) {
        self.paths = paths
    }

    /// `claude://code/continue?session=local_…`, which opens the session in the Claude desktop app.
    /// Nil for terminal sessions, which the desktop app doesn't know about.
    public func deepLink(forTranscript id: String) -> URL? {
        desktopSessionID(forTranscript: id).flatMap { URL(string: "claude://code/continue?session=\($0)") }
    }

    /// For terminal sessions: the command that reopens the conversation.
    public static func resumeCommand(forTranscript id: String) -> String {
        "claude --resume \(id)"
    }

    /// The desktop app stores each session's metadata under its own `local_…` id alongside the transcript id.
    func desktopSessionID(forTranscript id: String) -> String? {
        guard let files = FileManager.default.enumerator(at: paths.desktopSessions, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }

        var best: (id: String, modified: Date)?
        for case let file as URL in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (json["cliSessionId"] as? String) == id || (json["lastAssistantCliSessionId"] as? String) == id,
                  let local = json["sessionId"] as? String, local.hasPrefix("local_") else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if best == nil || modified > best!.modified { best = (local, modified) }
        }
        return best?.id
    }
}
