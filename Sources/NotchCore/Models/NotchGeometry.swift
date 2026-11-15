import CoreGraphics

public enum NotchMode: Equatable {
    /// Wings beside the physical notch.
    case collapsed
    /// A transient one-line alert.
    case peek
    /// The full session list.
    case expanded
    /// Permission prompts waiting for Allow/Deny.
    case request
}

/// Sizes and hit-testing for the notch panel, free of any UI framework so they can be tested.
public struct NotchGeometry {
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat

    public init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    // MARK: Constants

    /// The transparent window all modes are drawn inside; large enough for the tallest mode.
    public static let panelSize = CGSize(width: 460, height: 520)
    public static let listWidth: CGFloat = 440
    public static let wingWidth: CGFloat = 74
    public static let listInset: CGFloat = 12

    public static let sessionRowHeight: CGFloat = 68
    public static let rowSpacing: CGFloat = 6
    public static var sessionRowPitch: CGFloat { sessionRowHeight + rowSpacing }
    public static let maxSessionRows = 6

    public static let requestRowHeight: CGFloat = 78
    public static var requestRowPitch: CGFloat { requestRowHeight + rowSpacing }
    public static let maxRequestRows = 4
    public static let requestOverflowHeight: CGFloat = 22

    public static let peekHeight: CGFloat = 46
    public static let peekMinWidth: CGFloat = 400
    private static let bottomPadding: CGFloat = 20

    // MARK: Sizes

    public func size(for mode: NotchMode, sessionCount: Int, requestCount: Int) -> CGSize {
        let collapsedWidth = notchWidth + Self.wingWidth * 2
        switch mode {
        case .collapsed:
            return CGSize(width: collapsedWidth, height: notchHeight)
        case .peek:
            return CGSize(width: max(collapsedWidth, Self.peekMinWidth), height: notchHeight + Self.peekHeight)
        case .expanded:
            let rows = CGFloat(max(1, min(sessionCount, Self.maxSessionRows)))
            return CGSize(width: Self.listWidth, height: notchHeight + rows * Self.sessionRowPitch + Self.bottomPadding)
        case .request:
            let rows = CGFloat(min(requestCount, Self.maxRequestRows))
            let overflow = requestCount > Self.maxRequestRows ? Self.requestOverflowHeight : 0
            return CGSize(width: Self.listWidth, height: notchHeight + rows * Self.requestRowPitch + Self.bottomPadding + overflow)
        }
    }

    // MARK: Hit testing

    /// Which session card a point (in the notch's own coordinates, origin top-left) falls on.
    public func sessionRowIndex(at point: CGPoint, sessionCount: Int) -> Int? {
        let y = point.y - notchHeight
        guard y >= 0, point.x >= Self.listInset, point.x <= Self.listWidth - Self.listInset else { return nil }
        let index = Int(y / Self.sessionRowPitch)
        let offsetInRow = y - CGFloat(index) * Self.sessionRowPitch
        return index < min(sessionCount, Self.maxSessionRows) && offsetInRow <= Self.sessionRowHeight ? index : nil
    }
}
