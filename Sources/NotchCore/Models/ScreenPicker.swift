import Foundation

/// Decides which display the notch lives on, separate from AppKit so the rule can be tested.
public enum ScreenPicker {
    public struct Screen: Equatable {
        public let id: Int
        public let hasNotch: Bool
        public let isMain: Bool

        public init(id: Int, hasNotch: Bool, isMain: Bool) {
            self.id = id
            self.hasNotch = hasNotch
            self.isMain = isMain
        }
    }

    /// The display with a physical notch when there is one (the laptop's own screen, lid open), otherwise the main
    /// display (the external monitor when the lid is closed).
    public static func pick(from screens: [Screen]) -> Screen? {
        screens.first { $0.hasNotch } ?? screens.first { $0.isMain } ?? screens.first
    }
}
