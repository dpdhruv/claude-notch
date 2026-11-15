import SwiftUI
import AppKit
import Combine
import NotchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var model: NotchModel?
    private var pointerTimer: Timer?
    private var presenceObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = Self.notchScreen()
        // `.fullScreen` is set system-wide while a full-screen app (a film, a presentation) is in front.
        let model = NotchModel(geometry: Self.geometry(for: screen),
                               isFullScreenAppActive: { NSApp.currentSystemPresentationOptions.contains(.fullScreen) })
        self.model = model

        let size = NotchGeometry.panelSize
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let panel = NotchPanel(frame: frame)
        let host = NotchHostingView(rootView: NotchRootView(model: model))
        host.drawnSize = { [weak model] in model?.size ?? .zero }
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel

        // While hidden the panel is invisible and lets every click through.
        presenceObserver = model.$presence.sink { [weak panel] presence in
            panel?.alphaValue = presence == .hidden ? 0 : 1
            panel?.ignoresMouseEvents = presence == .hidden
        }

        model.start()
        if ProcessInfo.processInfo.environment["CLAUDE_NOTCH_EXPANDED"] != nil { model.forceExpanded() }
        trackPointer(on: screen)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    /// SwiftUI hover callbacks are unreliable in a non-key panel, so while the list is open the pointer is read
    /// directly. The model turns it into "which card is under the cursor".
    private func trackPointer(on screen: NSScreen) {
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let model = self?.model, model.mode == .expanded else { return }
            let mouse = NSEvent.mouseLocation
            let size = model.size
            let point = CGPoint(x: mouse.x - (screen.frame.midX - size.width / 2), y: screen.frame.maxY - mouse.y)
            if let old = model.pointer, abs(old.x - point.x) < 0.5, abs(old.y - point.y) < 0.5 { return }
            model.pointer = point
        }
    }

    // MARK: Screen

    /// The built-in display with a notch, else the main display.
    private static func notchScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The physical notch's size, or a notch-sized stand-in on Macs without one.
    private static func geometry(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(notchWidth: screen.frame.width - left.width - right.width, notchHeight: screen.safeAreaInsets.top)
        }
        return NotchGeometry(notchWidth: 190, notchHeight: NSStatusBar.system.thickness + 4)
    }
}
