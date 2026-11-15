import SwiftUI
import AppKit
import NotchCore

/// Renders the README screenshots offscreen from made-up data. No screen capture, so nothing real can leak in.
///
///     ClaudeNotch render-screenshots docs/images
@MainActor
enum ScreenshotRenderer {
    private static let geometry = NotchGeometry(notchWidth: 190, notchHeight: 32)
    private static let canvasWidth: CGFloat = 760

    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date()
        let sessions = DemoData.sessions(now: now)
        let approvals = DemoData.approvals(now: now)

        func model(mode: NotchMode, requests: [PermissionRequest] = [], alert: NotchAlert? = nil, pointer: CGPoint? = nil, serverMenu: String? = nil, sessions: [ClaudeSession] = sessions) -> NotchModel {
            let model = NotchModel(geometry: geometry,
                                   monitor: SessionMonitor(fixedSessions: sessions, now: now),
                                   broker: PermissionBroker(fixedPending: requests),
                                   linker: SessionLinker(),
                                   serverMonitor: ServerMonitor(fixed: DemoData.servers),
                                   preferences: UserDefaults(suiteName: "claude-notch-screenshots") ?? .standard)
            model.freeze(mode: mode, alert: alert, pointer: pointer, serverMenu: serverMenu)
            return model
        }

        let resting = sessions.filter { $0.state != .needsYou }
        let alert = NotchAlert(kind: .needsYou, title: "Fix flaky CI tests",
                               message: "Waiting to run Bash: npm test -- --runInBand", sessionID: "demo-ci")
        let hoverSecondCard = CGPoint(x: 220, y: geometry.notchHeight + NotchGeometry.sessionRowPitch + 34)

        let scenes: [(file: String, model: NotchModel, height: CGFloat)] = [
            ("collapsed.png", model(mode: .collapsed, sessions: resting), 110),
            ("alert.png", model(mode: .peek, alert: alert), 150),
            ("session-list.png", model(mode: .expanded, pointer: hoverSecondCard), 470),
            ("stop-server.png", model(mode: .expanded, serverMenu: "demo-checkout"), 470),
            ("settings.png", model(mode: .settings), 470),
            ("approvals.png", model(mode: .request, requests: approvals), 270),
        ]
        for scene in scenes {
            let image = Scene(model: scene.model, height: scene.height)
            guard let data = png(of: image, size: CGSize(width: canvasWidth, height: scene.height)) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: directory.appendingPathComponent(scene.file))
            print("wrote \(scene.file)")
        }
    }

    private static func png(of view: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(size)
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The top of a desktop: a wallpaper-ish gradient and a menu bar, with the notch panel on top.
    private struct Scene: View {
        let model: NotchModel
        let height: CGFloat

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.27), Color(red: 0.33, green: 0.17, blue: 0.42), Color(red: 0.88, green: 0.46, blue: 0.36)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                menuBar
                NotchRootView(model: model)
            }
            .frame(width: ScreenshotRenderer.canvasWidth, height: height, alignment: .top)
            .clipped()
        }

        private var menuBar: some View {
            HStack(spacing: 14) {
                Image(systemName: "apple.logo")
                Text("Terminal").fontWeight(.semibold)
                Text("Shell")
                Text("Edit")
                Text("View")
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("Sun 10:41")
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(height: geometry.notchHeight)
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.28))
        }
    }
}
