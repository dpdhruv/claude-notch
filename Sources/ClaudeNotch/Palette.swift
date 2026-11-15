import SwiftUI
import NotchCore

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let mint = Color(red: 0.36, green: 0.86, blue: 0.55)
    static let coral = Color(red: 1.0, green: 0.38, blue: 0.38)

    static func tint(for state: SessionState) -> Color {
        switch state {
        case .needsYou: return amber
        case .working: return claude
        case .done: return mint
        case .idle: return .gray
        }
    }
}

enum Motion {
    static let reveal = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let settle = Animation.spring(response: 0.4, dampingFraction: 0.85)
    static let alert = Animation.spring(response: 0.45, dampingFraction: 0.72)
    static let resize = Animation.spring(response: 0.45, dampingFraction: 0.8)
}
