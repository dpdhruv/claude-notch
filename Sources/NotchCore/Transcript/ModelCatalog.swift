import Foundation

/// Facts about Claude models that the transcript does not state.
public enum ModelCatalog {
    /// Context window in tokens, per Anthropic's models overview: 1M for the Fable and Mythos families, everything
    /// in the 5 generation, and Opus/Sonnet 4.6 and newer; 200k for older models.
    /// A session that has already used more than 200k tokens is, by definition, on the larger window.
    public static func contextWindow(for model: String, observedTokens: Int = 0) -> Int {
        if observedTokens > Config.standardContextWindow { return Config.extendedContextWindow }
        let id = model.lowercased()
        if id.contains("fable") || id.contains("mythos") { return Config.extendedContextWindow }
        guard let (family, major, minor) = parseVersion(id) else { return Config.standardContextWindow }
        if major >= 5 { return Config.extendedContextWindow }
        if major == 4, minor >= 6, family != "haiku" { return Config.extendedContextWindow }
        return Config.standardContextWindow
    }

    /// `claude-sonnet-5-5` becomes `Sonnet 5.5`.
    public static func displayName(for model: String) -> String {
        let id = model.lowercased()
        for family in ["fable", "mythos", "opus", "sonnet", "haiku"] where id.contains(family) {
            let numbers = id.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .filter { !$0.isEmpty && $0.count < 3 }   // skips date suffixes such as 20250929
            return family.capitalized + (numbers.isEmpty ? "" : " " + numbers.joined(separator: "."))
        }
        return model
    }

    /// Extracts `(family, major, minor)` from ids like `claude-opus-4-6` or `claude-sonnet-4-20250514`.
    private static func parseVersion(_ id: String) -> (family: String, major: Int, minor: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"(opus|sonnet|haiku)-(\d+)(?:-(\d{1,2}))?(?!\d)"#),
              let match = regex.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              let family = Range(match.range(at: 1), in: id),
              let major = Range(match.range(at: 2), in: id).flatMap({ Int(id[$0]) }) else { return nil }
        let minor = Range(match.range(at: 3), in: id).flatMap { Int(id[$0]) } ?? 0
        return (String(id[family]), major, minor)
    }
}
