import SwiftUI
import NotchCore

/// How each kind of alert looks, sounds and how long it stays.
extension NotchAlert.Kind {
    var symbol: String {
        switch self {
        case .needsYou: return "hand.raised.fill"
        case .done: return "checkmark.circle.fill"
        case .cacheLow: return "timer"
        case .cacheCold: return "snowflake"
        case .info: return "doc.on.clipboard"
        }
    }

    var tint: Color {
        switch self {
        case .needsYou: return Palette.amber
        case .done: return Palette.mint
        case .cacheLow: return Palette.coral
        case .cacheCold: return .cyan
        case .info: return .white
        }
    }

    /// A macOS system sound name, if any.
    var sound: String? {
        switch self {
        case .needsYou: return "Ping"
        case .done: return "Glass"
        case .cacheLow: return "Tink"
        case .cacheCold, .info: return nil
        }
    }

    var displayDuration: TimeInterval {
        switch self {
        case .needsYou: return 9
        case .done: return 5
        case .cacheLow: return 8
        case .cacheCold: return 6
        case .info: return 3.5
        }
    }
}
