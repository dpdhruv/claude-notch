import SwiftUI
import NotchCore

/// Permission prompts waiting for an answer, laid out like the session list.
struct RequestListView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let requests = model.requests
        let overflow = requests.count - NotchGeometry.maxRequestRows

        VStack(spacing: 0) {
            header(count: requests.count)
            VStack(spacing: NotchGeometry.rowSpacing) {
                ForEach(requests.prefix(NotchGeometry.maxRequestRows)) { request in
                    RequestRow(request: request, model: model)
                        .transition(.asymmetric(insertion: .scale(scale: 0.95).combined(with: .opacity),
                                                removal: .move(edge: .trailing).combined(with: .opacity)))
                }
                if overflow > 0 {
                    Text("+\(overflow) more waiting")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, NotchGeometry.listInset)
            .animation(Motion.settle, value: requests.map(\.id))
            Spacer(minLength: 0)
        }
    }

    private func header(count: Int) -> some View {
        NotchHeader(height: model.geometry.notchHeight, iconTint: Palette.amber,
                    status: "\(count) need\(count == 1 ? "s" : "") approval", statusTint: Palette.amber)
    }
}

/// One approval, laid out like a session card: a ring on the left, title and labels, the command, and the buttons.
struct RequestRow: View {
    let request: PermissionRequest
    @ObservedObject var model: NotchModel
    @State private var hoveringAllow = false
    @State private var hoveringDeny = false

    var body: some View {
        let info = model.sessionInfo(forID: request.sessionID)
        let risk = ToolDescriber.risk(tool: request.toolName, summary: request.summary)
        let accent = risk != nil ? Palette.coral : Palette.amber

        HStack(spacing: 12) {
            handoffRing(accent: accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(info.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Pill(text: ToolDescriber.displayName(of: request.toolName), tint: Palette.amber)
                    if let risk { Pill(text: risk, tint: Palette.coral) }
                }
                Text(request.summary.replacingOccurrences(of: "\n", with: " ⏎ "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                actions
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.6), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { model.open(sessionID: request.sessionID, title: info.title) }
        .frame(height: NotchGeometry.requestRowHeight)
    }

    /// Drains over the time left before the request is handed back to Claude's own dialog.
    private func handoffRing(accent: Color) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = context.date.timeIntervalSince(request.raisedAt)
            let fraction = max(0, min(1, 1 - elapsed / Config.permissionHandoff))
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 3)
                Circle().trim(from: 0, to: fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: ToolDescriber.icon(for: request.toolName))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 38, height: 38)
        .help("Time left before this goes back to Claude's own prompt")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.answer(request, .deferToApp) } label: {
                Text("Ask in app").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
            Button { model.answer(request, .deny) } label: {
                Text("Deny")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.coral)
                    .frame(width: 62, height: 24)
                    .background(Capsule().fill(Palette.coral.opacity(hoveringDeny ? 0.3 : 0.16)))
            }
            .buttonStyle(.plain)
            .onHover { hoveringDeny = $0 }
            Button { model.answer(request, .allow) } label: {
                Text("Allow")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 24)
                    .background(Capsule().fill(Palette.mint.opacity(hoveringAllow ? 1 : 0.88)))
            }
            .buttonStyle(.plain)
            .onHover { hoveringAllow = $0 }
        }
    }
}
