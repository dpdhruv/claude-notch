import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import NotchCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var screen: NSScreen!
    private var model: NotchModel?
    private var pointerTimer: Timer?
    private var presenceObserver: AnyCancellable?
    private let hotKeys = GlobalHotKeys()
    private var shortcutsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let screen = Self.notchScreen()
        self.screen = screen
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

        // ⌥⌘N denies and ⌥⌘Y allows the oldest waiting approval (see ApprovalShortcut for the safeguards).
        shortcutsObserver = model.$shortcutsEnabled.receive(on: DispatchQueue.main).sink { [weak self, weak model] enabled in
            guard enabled, let model else {
                self?.hotKeys.unregister()
                model?.shortcutsRegistered(2, of: 2)
                Self.recordShortcutStatus("off")
                return
            }
            let modifiers = optionKey | cmdKey
            let accepted = self?.hotKeys.register([
                .init(keyCode: kVK_ANSI_N, modifiers: modifiers) { model.answerFromKeyboard(.deny) },
                .init(keyCode: kVK_ANSI_Y, modifiers: modifiers) { model.answerFromKeyboard(.allow) },
            ]) ?? 0
            model.shortcutsRegistered(accepted, of: 2)
            Self.recordShortcutStatus(accepted == 2 ? "active" : "conflict (\(accepted) of 2 keys registered)")
        }
        model.start()
        if ProcessInfo.processInfo.environment["CLAUDE_NOTCH_EXPANDED"] != nil { model.forceExpanded() }
        trackPointer()
        // Docking, undocking, opening or closing the lid: follow the display the notch belongs on.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.followScreenChanges()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
    }

    /// The one place that watches the pointer (SwiftUI hover callbacks are unreliable in a non-key panel).
    ///
    /// Every tick it works out whether the pointer is on the notch and tells the model; and it keeps the window
    /// click-through except while the pointer is on something clickable, so the large transparent panel never
    /// swallows clicks meant for the app underneath (Chrome tabs, menu bar items…).
    private func trackPointer() {
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self, let model = self.model, let panel = self.panel else { return }
            let screen: NSScreen = self.screen

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

    /// So `ClaudeNotch status` can say whether the shortcuts took (another app may own the keys).
    private static func recordShortcutStatus(_ text: String) {
        try? text.write(to: Paths.live.shortcutStatus, atomically: true, encoding: .utf8)
    }

    // MARK: Screen

    /// Moves the notch to the right display and resizes it for that display's notch (or lack of one).
    private func followScreenChanges() {
        let target = Self.notchScreen()
        let size = NotchGeometry.panelSize
        panel?.setFrame(NSRect(x: target.frame.midX - size.width / 2, y: target.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        screen = target
        model?.updateGeometry(Self.geometry(for: target))
    }

    /// The display with a notch if there is one, else the main display (see `ScreenPicker`).
    private static func notchScreen() -> NSScreen {
        let screens = NSScreen.screens
        let infos = screens.enumerated().map { ScreenPicker.Screen(id: $0.offset, hasNotch: $0.element.safeAreaInsets.top > 0, isMain: $0.element == NSScreen.main) }
        return ScreenPicker.pick(from: infos).map { screens[$0.id] } ?? NSScreen.main ?? screens[0]
    }

    /// The physical notch's size, or a notch-sized stand-in on Macs without one.
    private static func geometry(for screen: NSScreen) -> NotchGeometry {
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(notchWidth: screen.frame.width - left.width - right.width, notchHeight: screen.safeAreaInsets.top)
        }
        return NotchGeometry(notchWidth: 190, notchHeight: NSStatusBar.system.thickness + 4)
    }
}
