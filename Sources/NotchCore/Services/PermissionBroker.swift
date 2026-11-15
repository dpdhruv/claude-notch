import Foundation
import Combine

/// File-based bridge to the `PermissionRequest` hook (`notch-permission.sh`).
///
/// 1. Claude Code is about to show a permission dialog and runs the hook.
/// 2. The hook writes `requests/<id>.json` and waits for `responses/<id>.json`.
/// 3. This broker publishes the request; the user answers in the notch; the broker writes the response.
/// 4. The hook prints the decision to Claude Code. If nothing answers in time, the hook prints nothing and the
///    normal dialog appears, so a closed or crashed app can never block a session.
public final class PermissionBroker: ObservableObject {
    /// Oldest first.
    @Published public private(set) var pending: [PermissionRequest] = []

    private let paths: Paths
    private var pollTimer: Timer?
    private var heartbeatTimer: Timer?

    public init(paths: Paths = .live) {
        self.paths = paths
    }

    /// A broker frozen on the given requests, never touching the disk (for documentation screenshots).
    public init(fixedPending: [PermissionRequest]) {
        self.paths = .live
        self.pending = fixedPending
    }

    public func start() {
        stop()
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.permissionRequests, withIntermediateDirectories: true)
        try? fm.createDirectory(at: paths.permissionResponses, withIntermediateDirectories: true)
        touchHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Config.heartbeatInterval, repeats: true) { [weak self] _ in self?.touchHeartbeat() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: Config.permissionPollInterval, repeats: true) { [weak self] _ in self?.poll() }
    }

    /// Stops polling and removes the heartbeat, so hooks immediately fall back to Claude's own dialog.
    public func stop() {
        pollTimer?.invalidate()
        heartbeatTimer?.invalidate()
        try? FileManager.default.removeItem(at: paths.heartbeat)
    }

    public func respond(to request: PermissionRequest, with decision: PermissionDecision) {
        try? FileManager.default.createDirectory(at: paths.permissionResponses, withIntermediateDirectories: true)
        let temporary = paths.permissionResponses.appendingPathComponent(".\(request.id).tmp")
        let final = paths.permissionResponses.appendingPathComponent("\(request.id).json")
        try? decision.hookOutput.write(to: temporary, atomically: false, encoding: .utf8)
        try? FileManager.default.moveItem(at: temporary, to: final)   // rename is atomic, so the hook never sees half a file
        try? FileManager.default.removeItem(at: requestFile(request.id))
        pending.removeAll { $0.id == request.id }
    }

    // MARK: Polling

    private func touchHeartbeat() {
        FileManager.default.createFile(atPath: paths.heartbeat.path, contents: Data("1".utf8))
    }

    private func requestFile(_ id: String) -> URL {
        paths.permissionRequests.appendingPathComponent("\(id).json")
    }

    func poll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: paths.permissionRequests, includingPropertiesForKeys: nil) else { return }

        var found: [PermissionRequest] = []
        for file in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else { continue }

            // The hook process is gone: the prompt was answered in Claude's own dialog, or timed out.
            if let pid = json["pid"] as? Int, kill(pid_t(pid), 0) != 0 {
                try? fm.removeItem(at: file)
                continue
            }
            let payload = json["payload"] as? [String: Any] ?? [:]
            let tool = payload["tool_name"] as? String ?? "tool"
            found.append(PermissionRequest(
                id: id,
                sessionID: payload["session_id"] as? String ?? "",
                toolName: tool,
                summary: ToolDescriber.summary(of: tool, input: payload["tool_input"] as? [String: Any]),
                detail: ToolDescriber.detail(of: tool, input: payload["tool_input"] as? [String: Any]),
                directory: (payload["cwd"] as? String).map(ToolDescriber.abbreviatingHome),
                raisedAt: Date(timeIntervalSince1970: json["ts"] as? Double ?? 0)))
        }
        // Oldest first; requests raised in the same second keep a stable order, so the keyboard shortcut and the top card agree.
        found.sort { ($0.raisedAt, $0.id) < ($1.raisedAt, $1.id) }
        if found != pending { pending = found }
    }
}
