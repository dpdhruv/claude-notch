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

        HStack(alignment: .top, spacing: 12) {
            handoffRing(accent: accent)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.detail.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let risk { Pill(text: risk, tint: Palette.coral) }
                }
                subtitle(request.detail, session: info.title)
                if !request.detail.lines.isEmpty { codeBox(request.detail.lines, accent: accent) }
                Spacer(minLength: 0)
                actions
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.6), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { model.open(sessionID: request.sessionID, title: info.title) }
        .frame(height: NotchGeometry.requestRowHeight(bodyLines: request.detail.lines.count))
    }

    /// The kind of action (when the title is Claude's own words), then the file involved and the session it came from.
    private func subtitle(_ detail: RequestDetail, session: String) -> some View {
        HStack(spacing: 6) {
            if detail.explanation != nil {
                Text(detail.headline)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                    .layoutPriority(1)
            }
            Text([detail.location, session].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
                .truncationMode(.middle)
        }
        .lineLimit(1)
    }

    /// The exact command or change, with removed and added lines coloured like a diff.
    private func codeBox(_ lines: [RequestDetail.Line], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 5) {
                    Text(marker(for: line.kind))
                        .frame(width: 8, alignment: .leading)
                    Text(line.text.isEmpty ? " " : line.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 10.5, design: line.kind == .note ? .default : .monospaced))
                .foregroundStyle(color(for: line.kind))
                .frame(height: NotchGeometry.requestLineHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.45)))
    }

    private func marker(for kind: RequestDetail.Line.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .plain: return "›"
        case .note: return ""
        }
    }

    private func color(for kind: RequestDetail.Line.Kind) -> Color {
        switch kind {
        case .added: return Palette.mint
        case .removed: return Palette.coral
        case .plain: return .white.opacity(0.85)
        case .note: return .white.opacity(0.4)
        }
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
