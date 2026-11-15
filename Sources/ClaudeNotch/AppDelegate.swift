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
                               isFullScreenAppActive: { NSApp.currentSystemPresentationOptions.contains(.fullScreen) },
                               frontmostBundleID: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier })
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

    /// The one place that watches the pointer (SwiftUI hover callbacks are unreliable in a non-key panel).
    ///
    /// Every tick it works out whether the pointer is on the notch and tells the model; and it keeps the window
    /// click-through except while the pointer is on something clickable, so the large transparent panel never
    /// swallows clicks meant for the app underneath (Chrome tabs, menu bar items…).
    private func trackPointer(on screen: NSScreen) {
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let model = self.model, let panel = self.panel else { return }

            let mouse = NSEvent.mouseLocation   // screen coordinates, origin bottom-left
            let drawn = model.size
            let zone = model.geometry.hotZone(for: model.mode, drawnSize: drawn)
            let onNotch = abs(mouse.x - screen.frame.midX) <= zone.width / 2
                && mouse.y <= screen.frame.maxY + 1 && mouse.y >= screen.frame.maxY - zone.height
            let hovering = onNotch && model.presence != .hidden

            if hovering != model.isHovering { hovering ? model.pointerEntered() : model.pointerExited() }
            if hovering && model.mode == .expanded {
                // Convert to the notch's own coordinates (origin top-left) for card hit-testing.
                let point = CGPoint(x: mouse.x - (screen.frame.midX - drawn.width / 2), y: screen.frame.maxY - mouse.y)
                if let old = model.pointer, abs(old.x - point.x) < 0.5, abs(old.y - point.y) < 0.5 {} else { model.pointer = point }
            }
            panel.ignoresMouseEvents = !(hovering && NotchGeometry.acceptsClicks(in: model.mode))
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
