import SwiftUI
import NotchCore

/// The row level with the physical notch: the app name on the left, a short status on the right.
struct NotchHeader: View {
    let height: CGFloat
    let iconTint: Color
    let status: String
    let statusTint: Color

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").foregroundStyle(iconTint)
                Text("Claude").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.leading, 22)
            Spacer()
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(statusTint)
                .padding(.trailing, 22)
        }
        .frame(height: height)
    }
}
