import SwiftUI
import NotchCore

/// "● :5173" for a server a session left running; "+1" when there are more. Click to manage them.
struct ServerChip: View {
    let servers: [RunningServer]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle().fill(Palette.mint).frame(width: 5, height: 5)
                Text(":\(servers[0].port)" + (servers.count > 1 ? " +\(servers.count - 1)" : ""))
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Palette.mint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette.mint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(servers.map { "\($0.name) on port \($0.port)" }.joined(separator: "\n") + "\nClick to stop")
    }
}

/// Replaces a card's contents while its servers are open: each with a Stop button that asks once before acting.
struct ServerMenu: View {
    let servers: [RunningServer]
    let stopping: [String: Date]
    let now: Date
    let onStop: (RunningServer, Bool) -> Void
    let onClose: () -> Void
    private static let visibleRows = 2

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                ForEach(servers.prefix(Self.visibleRows)) { server in
                    ServerMenuRow(server: server, stoppingSince: stopping[server.id], now: now, onStop: onStop)
                }
                if servers.count > Self.visibleRows {
                    Text("+\(servers.count - Self.visibleRows) more").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.mint.opacity(0.35), lineWidth: 1))
    }
}

struct ServerMenuRow: View {
    let server: RunningServer
    let stoppingSince: Date?
    let now: Date
    let onStop: (RunningServer, Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.mint).frame(width: 5, height: 5)
            Text(server.name).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white).lineLimit(1)
            Text(verbatim: ":" + String(server.port)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            if server.managedByApp {
                Text("app-managed").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).help("Started by the Claude app's preview, which may start it again")
            }
            Spacer(minLength: 4)
            ServerStopControl(server: server, stoppingSince: stoppingSince, now: now, onStop: onStop)
        }
        .frame(height: 22)
    }
}

/// Stop, then "Stop it? Yes / No", then "Stopping…", then Force stop if the server ignores the polite request.
struct ServerStopControl: View {
    let server: RunningServer
    let stoppingSince: Date?
    let now: Date
    let onStop: (RunningServer, Bool) -> Void
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 6) {
            if let since = stoppingSince {
                if now.timeIntervalSince(since) > Config.forceStopAfter {
                    button("Force stop", tint: Palette.coral, filled: true) { onStop(server, true) }
                } else {
                    Text("Stopping…").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
            } else if confirming {
                Text("Stop it?").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                button("Yes", tint: Palette.coral, filled: true) { confirming = false; onStop(server, false) }
                button("No", tint: .white.opacity(0.6), filled: false) { confirming = false }
            } else {
                Button { confirming = true } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.coral)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.coral.opacity(0.18)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Stop this server")
            }
        }
    }

    private func button(_ title: String, tint: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(filled ? Color.black : tint)
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Capsule().fill(filled ? tint : tint.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

/// The Servers tab: every server any session has running, with its session and a Stop button.
struct ServersView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let servers = model.allServers
        let slots = NotchGeometry.settingsRowCount
        let shown = servers.count > slots ? slots - 1 : servers.count

        VStack(spacing: 0) {
            NotchHeader(height: model.geometry.notchHeight, iconTint: Palette.claude,
                        status: servers.isEmpty ? "none running" : "\(servers.count) running", statusTint: .white.opacity(0.55))
            VStack(spacing: NotchGeometry.rowSpacing) {
                if servers.isEmpty {
                    Text("No servers left running by your sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: NotchGeometry.settingsRowHeight)
                }
                ForEach(servers.prefix(shown)) { server in
                    SettingRowFrame(title: server.name + "  :" + String(server.port),
                                    detail: model.sessionInfo(forID: server.sessionID).title + (server.managedByApp ? " · app-managed" : "")) {
                        ServerStopControl(server: server, stoppingSince: model.stoppingServers[server.id], now: model.monitor.now,
                                          onStop: { model.stopServer($0, force: $1) })
                    }
                }
                if servers.count > shown {
                    Text("+\(servers.count - shown) more. Open a session card to manage its servers.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(height: NotchGeometry.settingsRowHeight)
                }
            }
            .padding(.horizontal, NotchGeometry.listInset)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}
