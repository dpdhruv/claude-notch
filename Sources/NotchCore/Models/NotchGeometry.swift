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
    /// The settings page, a tab next to the list.
    case settings
    /// Every server the sessions have running, a tab next to the list.
    case servers

    /// The three pages that share the tab bar along the bottom.
    public var isTabbedPage: Bool { self == .expanded || self == .settings || self == .servers }
}

/// Sizes and hit-testing for the notch panel, free of any UI framework so they can be tested.
public struct NotchGeometry: Equatable {
    public let notchWidth: CGFloat
    public let notchHeight: CGFloat

    public init(notchWidth: CGFloat, notchHeight: CGFloat) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
    }

    // MARK: Constants

    /// The transparent window all modes are drawn inside; large enough for the tallest mode.
    public static let panelSize = CGSize(width: 460, height: 640)
    public static let listWidth: CGFloat = 440
    public static let wingWidth: CGFloat = 74
    public static let listInset: CGFloat = 12

    public static let sessionRowHeight: CGFloat = 68
    public static let rowSpacing: CGFloat = 6
    public static var sessionRowPitch: CGFloat { sessionRowHeight + rowSpacing }
    public static let maxSessionRows = 6

    /// An approval card: header, headline and buttons around a code box that grows with the lines it shows.
    public static let requestChromeHeight: CGFloat = 96
    public static let requestLineHeight: CGFloat = 14
    public static let maxRequestRows = 3
    public static func requestRowHeight(bodyLines: Int) -> CGFloat {
        requestChromeHeight + CGFloat(max(0, bodyLines)) * requestLineHeight
    }
    public static let requestOverflowHeight: CGFloat = 22

    public static let settingsRowHeight: CGFloat = 40
    public static let settingsRowCount = 6

    public static let peekHeight: CGFloat = 46
    public static let peekMinWidth: CGFloat = 400
    private static let bottomPadding: CGFloat = 20
    /// The Sessions / Settings tabs along the bottom of the list and the settings page.
    public static let tabBarHeight: CGFloat = 40

    // MARK: Sizes

    /// `requestBodyLines` holds how many code lines each waiting approval shows, oldest first.
    public func size(for mode: NotchMode, sessionCount: Int, requestCount: Int, requestBodyLines: [Int] = []) -> CGSize {
        let collapsedWidth = notchWidth + Self.wingWidth * 2
        switch mode {
        case .collapsed:
            return CGSize(width: collapsedWidth, height: notchHeight)
        case .peek:
            return CGSize(width: max(collapsedWidth, Self.peekMinWidth), height: notchHeight + Self.peekHeight)
        case .expanded, .settings, .servers:
            return CGSize(width: Self.listWidth, height: tabbedHeight(sessionCount: sessionCount))
        case .request:
            let shown = min(requestCount, Self.maxRequestRows)
            let rows = (0..<shown).reduce(CGFloat(0)) { total, index in
                total + Self.requestRowHeight(bodyLines: index < requestBodyLines.count ? requestBodyLines[index] : 1) + Self.rowSpacing
            }
            let overflow = requestCount > Self.maxRequestRows ? Self.requestOverflowHeight : 0
            return CGSize(width: Self.listWidth, height: notchHeight + rows + Self.bottomPadding + overflow)
        }
    }

    /// Sessions, Servers and Settings share one height, so switching tabs never moves the tab bar out from under the pointer
    /// (which would count as leaving the notch and close it).
    private func tabbedHeight(sessionCount: Int) -> CGFloat {
        let listRows = CGFloat(max(1, min(sessionCount, Self.maxSessionRows)))
        let list = listRows * Self.sessionRowPitch
        let settings = CGFloat(Self.settingsRowCount) * (Self.settingsRowHeight + Self.rowSpacing)
        return notchHeight + max(list, settings) + Self.tabBarHeight
    }

    // MARK: Pointer interaction

    /// The region that reacts to the pointer. While collapsed, only the physical notch (plus a hair) counts, so the
    /// decorative wings never get in the way of the menu bar items underneath them.
    public func hotZone(for mode: NotchMode, drawnSize: CGSize) -> CGSize {
        mode == .collapsed ? CGSize(width: notchWidth + 16, height: notchHeight + 2) : drawnSize
    }

    /// Only the list, the approval cards and the settings page have anything to click. In other modes the window lets every click through.
    public static func acceptsClicks(in mode: NotchMode) -> Bool {
        mode.isTabbedPage || mode == .request
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
