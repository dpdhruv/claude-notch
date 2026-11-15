import Foundation

public enum Format {
    /// `4:05` under an hour, `1h 02m` above.
    public static func duration(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        return s >= 3600
            ? String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// `850`, `212k`, `1M`, `1.2M`.
    public static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000
            return millions == millions.rounded() ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        return count >= 1000 ? "\(count / 1000)k" : "\(count)"
    }
}
