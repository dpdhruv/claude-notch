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
                    SessionRow(session: session, now: model.monitor.now, isHovered: model.hoveredRow == index)
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
            Toggle("Stay quiet in full screen", isOn: Binding(get: { model.policy.quietInFullScreen },
                                                                set: { model.setQuietInFullScreen($0) }))
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
        NotchHeader(height: model.geometry.notchHeight, iconTint: Palette.claude, status: summary, statusTint: .white.opacity(0.55))
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
    let now: Date
    let isHovered: Bool

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
                    Pill(text: session.state.label, tint: tint)
                }
                Text(session.detail.isEmpty ? "\(session.project) · \(Format.duration(now.timeIntervalSince(session.lastActivity))) ago" : session.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
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
        .scaleEffect(isHovered ? 1.012 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .frame(height: NotchGeometry.sessionRowHeight)
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
