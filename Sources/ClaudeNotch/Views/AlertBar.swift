import SwiftUI
import NotchCore

/// A transient one-line alert dropped below the notch.
struct AlertBar: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        if let alert = model.alert {
            VStack(spacing: 0) {
                Spacer().frame(height: model.geometry.notchHeight)
                HStack(spacing: 10) {
                    Image(systemName: alert.kind.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(alert.kind.tint)
                        .symbolEffect(.bounce, value: alert)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(alert.message)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 22)
                .frame(height: NotchGeometry.peekHeight)
            }
        }
    }
}
