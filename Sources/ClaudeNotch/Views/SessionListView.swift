import SwiftUI
import NotchCore

/// The expanded notch: one card per session.
struct SessionListView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: NotchGeometry.rowSpacing) {
                if model.sessions.isEmpty {
                    Text("No active sessions")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(height: NotchGeometry.sessionRowHeight)
                }
                ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                    SessionRow(session: session, servers: model.servers[session.id] ?? [], now: model.monitor.now,
                               isHovered: model.hoveredRow == index, serverMenuOpen: model.serverMenuSessionID == session.id,
                               stopping: model.stoppingServers,
                               onToggleServers: { model.toggleServerMenu(forSession: session.id) },
                               onStop: { server, force in model.stopServer(server, force: force) })
                }
            }
            .padding(.horizontal, NotchGeometry.listInset)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        // Per-row hover/tap callbacks are unreliable in a non-key panel, so rows are resolved from pointer geometry.
        .gesture(SpatialTapGesture().onEnded { tap in
            if let row = model.geometry.sessionRowIndex(at: tap.location, sessionCount: model.sessions.count) {
                model.openSession(atRow: row)
            }
        })
        .contextMenu {
            Button("Settings") { model.showSettings() }
            if model.isPaused {
                Button("Resume alerts") { model.resumeAlerts() }
            } else {
                Button("Pause alerts for 1 hour") { model.pauseAlerts() }
            }
            Divider()
            Button("Quit Claude Notch") { NSApp.terminate(nil) }
        }
        .transition(.opacity)
    }

    private var header: some View {
        NotchHeader(height: model.geometry.notchHeight, iconTint: Palette.claude, status: summary, statusTint: .white.opacity(0.55),
                    onSettings: { model.showSettings() })
    }

    private var summary: String {
        var parts: [String] = []
        if model.needsYouCount > 0 { parts.append("\(model.needsYouCount) need you") }
        if model.workingCount > 0 { parts.append("\(model.workingCount) working") }
        return parts.isEmpty ? "all quiet" : parts.joined(separator: " · ")
    }
}

struct SessionRow: View {
    let session: ClaudeSession
    let servers: [RunningServer]
    let now: Date
    let isHovered: Bool
    let serverMenuOpen: Bool
    let stopping: [String: Date]
    let onToggleServers: () -> Void
    let onStop: (RunningServer, Bool) -> Void

    var body: some View {
        let tint = Palette.tint(for: session.state)
        let needsYou = session.state == .needsYou

        HStack(spacing: 12) {
            CacheRing(session: session, now: now)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if session.isTerminal {
                        Image(systemName: "terminal")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .help("Started from the terminal")
                    }
                    Pill(text: session.state.label, tint: tint)
                }
                HStack(spacing: 6) {
                    Text(session.detail.isEmpty ? "\(session.project) · \(Format.duration(now.timeIntervalSince(session.lastActivity))) ago" : session.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !servers.isEmpty { ServerChip(servers: servers, action: onToggleServers) }
                }
                ContextBar(context: session.context, model: session.model)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity((needsYou ? 0.1 : 0.05) + (isHovered ? 0.08 : 0))))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(needsYou ? Palette.amber.opacity(0.6) : (isHovered ? .white.opacity(0.22) : .clear), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(9)
                .opacity(isHovered ? 1 : 0)
        }
        .overlay {
            if serverMenuOpen {
                ServerMenu(servers: servers, stopping: stopping, now: now, onStop: onStop, onClose: onToggleServers)
            }
        }
        .scaleEffect(isHovered ? 1.012 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .frame(height: NotchGeometry.sessionRowHeight)
    }
}

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
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.mint).frame(width: 5, height: 5)
            Text(server.name).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white).lineLimit(1)
            Text(verbatim: ":" + String(server.port)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            if server.managedByApp {
                Text("app-managed").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).help("Started by the Claude app's preview, which may start it again")
            }
            Spacer(minLength: 4)
            control
        }
        .frame(height: 22)
    }

    @ViewBuilder private var control: some View {
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
            button("Stop", tint: Palette.coral, filled: false) { confirming = true }
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

/// A small uppercase label such as `WORKING`.
struct Pill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.6)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

/// How full the context window is: a thin bar plus the numbers.
struct ContextBar: View {
    let context: ContextUsage
    let model: String

    private var tint: Color {
        context.fraction > 0.85 ? Palette.coral : context.fraction > 0.65 ? Palette.amber : .white.opacity(0.55)
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(tint).frame(width: proxy.size.width * context.fraction)
                }
            }
            .frame(height: 3)
            Text("\(context.label) · \(model)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize()
        }
    }
}

/// The prompt-cache countdown: a ring that drains, then a snowflake once the cache is cold.
struct CacheRing: View {
    let session: ClaudeSession
    let now: Date

    var body: some View {
        let isWorking = session.state == .working
        let remaining = isWorking ? (session.cache?.lifetime ?? 0) : (session.cache?.remaining(at: now) ?? 0)
        let fraction = isWorking ? 1 : (session.cache?.fractionRemaining(at: now) ?? 0)
        let tint = ringTint(isWorking: isWorking, remaining: remaining, fraction: fraction)

        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 3)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isWorking {
                ActivityDots()
            } else if remaining <= 0 {
                Image(systemName: "snowflake").font(.system(size: 11)).foregroundStyle(.cyan.opacity(0.8))
            } else {
                Text(Format.duration(remaining))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 38, height: 38)
        .help(session.cache?.isLongLived == true ? "1-hour prompt cache" : "5-minute prompt cache")
    }

    private func ringTint(isWorking: Bool, remaining: TimeInterval, fraction: Double) -> Color {
        if isWorking { return Palette.claude }
        if remaining <= 0 { return .gray }
        if remaining < 60 || fraction < 0.2 { return Palette.coral }
        return fraction < 0.5 ? Palette.amber : Palette.mint
    }
}
