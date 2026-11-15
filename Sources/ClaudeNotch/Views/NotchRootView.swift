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
        case .expanded: SessionListView(model: model)
        case .request: RequestListView(model: model)
        case .settings: SettingsView(model: model)
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
