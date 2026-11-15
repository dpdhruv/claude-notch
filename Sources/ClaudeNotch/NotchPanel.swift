import SwiftUI
import AppKit
import NotchCore

/// A borderless, non-activating panel floating above the menu bar. It never takes focus from the app you are using.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
    }
}

/// Hosts the SwiftUI view, but only responds to the mouse where the notch is actually drawn, so the large transparent
/// window around it never blocks clicks on whatever is underneath.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    /// The notch's current drawn size, anchored top-centre.
    var drawnSize: () -> CGSize = { .zero }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let size = drawnSize()
        let local = superview.map { convert(point, from: $0) } ?? point   // `point` is in the superview's coordinates
        let originY = isFlipped ? 0 : bounds.height - size.height
        let drawn = NSRect(x: (bounds.width - size.width) / 2, y: originY, width: size.width, height: size.height)
        return drawn.contains(local) ? super.hitTest(point) : nil
    }
}
