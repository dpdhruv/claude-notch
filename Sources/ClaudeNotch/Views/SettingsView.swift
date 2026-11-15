import SwiftUI
import NotchCore

/// The settings page, drawn inside the notch: a few switches, pause and quit.
struct SettingsView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: NotchGeometry.rowSpacing) {
                SettingSwitchRow(title: "Quiet in full screen", detail: "Hide completely while a film or presentation is up",
                                 isOn: model.policy.quietInFullScreen) { model.setQuietInFullScreen($0) }
                SettingSwitchRow(title: "Quiet when Claude is in front", detail: "Hold approvals back; hover the notch to see them",
                                 isOn: model.policy.quietWhenClaudeInFront) { model.setQuietWhenClaudeInFront($0) }
                SettingSwitchRow(title: "Sounds", detail: "Play a sound for alerts and approvals",
                                 isOn: model.soundsEnabled) { model.setSoundsEnabled($0) }
                SettingSwitchRow(title: "Keyboard shortcuts", detail: model.shortcutsConflict ? "Another app already uses ⌥⌘Y or ⌥⌘N" : "⌥⌘Y allows and ⌥⌘N denies the oldest approval",
                                 isOn: model.shortcutsEnabled) { model.setShortcutsEnabled($0) }
                SettingButtonRow(title: model.isPaused ? "Alerts are paused" : "Pause alerts",
                                 detail: model.isPaused ? "No sounds or drop-downs right now" : "No sounds or drop-downs for an hour",
                                 action: model.isPaused ? "Resume" : "Pause 1h", tint: Palette.amber) {
                    model.isPaused ? model.resumeAlerts() : model.pauseAlerts()
                }
                SettingButtonRow(title: "Claude Notch \(Config.version)", detail: "Stops the app; hooks fall back to Claude's own prompts",
                                 action: "Quit", tint: Palette.coral) { NSApp.terminate(nil) }
            }
            .padding(.horizontal, NotchGeometry.listInset)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    private var header: some View {
        NotchHeader(height: model.geometry.notchHeight, iconTint: Palette.claude, status: "Settings", statusTint: .white.opacity(0.55))
    }
}

struct SettingRowFrame<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: NotchGeometry.settingsRowHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}

private struct SettingSwitchRow: View {
    let title: String
    let detail: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        SettingRowFrame(title: title, detail: detail) {
            // Drawn by hand: the system switch looks disabled in a window that never becomes key.
            Button { set(!isOn) } label: {
                Capsule()
                    .fill(isOn ? Palette.mint : .white.opacity(0.18))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: isOn)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingButtonRow: View {
    let title: String
    let detail: String
    let action: String
    let tint: Color
    let perform: () -> Void

    var body: some View {
        SettingRowFrame(title: title, detail: detail) {
            Button(action: perform) {
                Text(action)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(tint.opacity(0.16)))
            }
            .buttonStyle(.plain)
        }
    }
}
