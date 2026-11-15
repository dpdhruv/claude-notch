import Foundation

/// The most recent Claude Code hook event for a session, as recorded by `notch-hook.sh`.
struct HookEvent: Equatable {
    let event: String
    let timestamp: Date
    /// For `Notification` events: `permission_prompt`, `idle_prompt`, …
    let notificationType: String?
    let message: String?
}

struct HookStateStore {
    let paths: Paths

    func latestEvent(forSession id: String) -> HookEvent? {
        let file = paths.hookStates.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = json["event"] as? String,
              let seconds = json["ts"] as? Double else { return nil }
        let payload = json["payload"] as? [String: Any]
        return HookEvent(event: event,
                         timestamp: Date(timeIntervalSince1970: seconds),
                         notificationType: payload?["notification_type"] as? String,
                         message: payload?["message"] as? String)
    }
}
