import SwiftUI
import NotchCore

/// The resting state: two small wings either side of the physical notch.
struct CollapsedBar: View {
    @ObservedObject var model: NotchModel
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 0) {
            leftWing.frame(width: NotchGeometry.wingWidth)
            Spacer().frame(width: model.geometry.notchWidth)
            rightWing.frame(width: NotchGeometry.wingWidth)
        }
        .frame(height: model.geometry.notchHeight)
    }

    private var leftWing: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(model.needsYouCount > 0 ? Palette.amber : Palette.claude)
                .symbolEffect(.pulse, isActive: model.workingCount > 0)
            if model.workingCount > 0 { ActivityDots() }
            if model.presence == .quiet {
                Image(systemName: "bell.slash.fill").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    /// Shows the most important thing: approvals waiting, a cache about to expire, work in progress, or "all quiet".
    @ViewBuilder private var rightWing: some View {
        if model.needsYouCount > 0 {
            Text("\(model.needsYouCount)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Palette.amber))
                .scaleEffect(pulse ? 1.18 : 0.95)
                .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
        } else if let next = model.nextCacheExpiry, next.remaining < next.cache.countdownThreshold {
            Text(Format.duration(next.remaining))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(next.remaining < 60 ? Palette.coral : .white.opacity(0.6))
        } else if model.workingCount > 0 {
            Text("\(model.workingCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.claude)
        } else {
            Circle()
                .fill(model.monitor.sessions.isEmpty ? Color.gray.opacity(0.4) : Palette.mint)
                .frame(width: 6, height: 6)
        }
    }
}

/// Three dots that ripple while something is working.
struct ActivityDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Palette.claude)
                        .frame(width: 3.5, height: 3.5)
                        .opacity(0.35 + 0.65 * max(0, sin(t * 5 - Double(index) * 0.8)))
                }
            }
        }
    }
}
