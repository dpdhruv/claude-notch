import SwiftUI
import NotchCore

/// The black notch-shaped surface that every mode is drawn on, anchored to the top of the transparent panel.
struct NotchRootView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let size = model.size
        let radius: CGFloat = model.mode == .collapsed ? 12 : 26

        ZStack(alignment: .top) {
            NotchShape(radius: radius)
                .fill(Color.black)
                .shadow(color: .black.opacity(model.mode == .collapsed ? 0 : 0.5), radius: 18, y: 8)
            content
        }
        .frame(width: size.width, height: size.height)
        .clipShape(NotchShape(radius: radius))
        .frame(width: NotchGeometry.panelSize.width, height: NotchGeometry.panelSize.height, alignment: .top)
        .animation(Motion.resize, value: model.mode)
        .animation(Motion.resize, value: model.sessions.count)
    }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .collapsed: CollapsedBar(model: model)
        case .peek: AlertBar(model: model)
        case .expanded: TabbedPage(model: model) { SessionListView(model: model) }
        case .request: RequestListView(model: model)
        case .servers: TabbedPage(model: model) { ServersView(model: model) }
        case .settings: TabbedPage(model: model) { SettingsView(model: model) }
        }
    }
}

/// Flat top (it merges with the screen edge), rounded bottom corners.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A page with the Sessions / Settings tabs along the bottom.
struct TabbedPage<Content: View>: View {
    @ObservedObject var model: NotchModel
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            HStack(spacing: 6) {
                tab("Sessions", icon: "square.stack.fill", page: .expanded)
                tab("Servers", icon: "server.rack", page: .servers, badge: model.allServers.count)
                tab("Settings", icon: "gearshape.fill", page: .settings)
            }
            .padding(.horizontal, NotchGeometry.listInset)
            .frame(height: NotchGeometry.tabBarHeight, alignment: .top)
        }
    }

    private func tab(_ title: String, icon: String, page: NotchMode, badge: Int = 0) -> some View {
        let selected = model.mode == page
        return Button { model.showPage(page) } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
                if badge > 0 {
                    Text(verbatim: String(badge))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Palette.mint))
                }
            }
            .foregroundStyle(selected ? Color.white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(Capsule().fill(.white.opacity(selected ? 0.14 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
