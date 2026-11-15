import XCTest
@testable import NotchCore

final class ModelCatalogTests: XCTestCase {
    func testFiveGenerationAndFableHaveTheLargeWindow() {
        for model in ["claude-sonnet-5-5", "claude-opus-5-5", "claude-haiku-5-5", "claude-fable-5-2", "claude-mythos-5-1"] {
            XCTAssertEqual(ModelCatalog.contextWindow(for: model), 1_000_000, model)
        }
    }

    func testOpusAndSonnetFromFourPointSixHaveTheLargeWindow() {
        for model in ["claude-opus-4-6", "claude-opus-4-8", "claude-sonnet-4-6"] {
            XCTAssertEqual(ModelCatalog.contextWindow(for: model), 1_000_000, model)
        }
    }

    func testOlderModelsHaveTheStandardWindow() {
        for model in ["claude-sonnet-4-5-20250929", "claude-haiku-4-5", "claude-opus-4-1", "claude-sonnet-4-20250514", "something-else", ""] {
            XCTAssertEqual(ModelCatalog.contextWindow(for: model), 200_000, model)
        }
    }

    func testObservedUsageAboveTheStandardWindowProvesTheLargeOne() {
        XCTAssertEqual(ModelCatalog.contextWindow(for: "claude-sonnet-4-5", observedTokens: 250_000), 1_000_000)
        XCTAssertEqual(ModelCatalog.contextWindow(for: "claude-sonnet-4-5", observedTokens: 150_000), 200_000)
    }

    func testDisplayNames() {
        XCTAssertEqual(ModelCatalog.displayName(for: "claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(ModelCatalog.displayName(for: "claude-fable-5-2"), "Fable 5.2")
        XCTAssertEqual(ModelCatalog.displayName(for: "claude-sonnet-4-5-20250929"), "Sonnet 4.5")
        XCTAssertEqual(ModelCatalog.displayName(for: "<synthetic>"), "<synthetic>")
        XCTAssertEqual(ModelCatalog.displayName(for: ""), "")
    }
}

final class FormatTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Format.duration(0), "0:00")
        XCTAssertEqual(Format.duration(65), "1:05")
        XCTAssertEqual(Format.duration(299.9), "4:59")
        XCTAssertEqual(Format.duration(3725), "1h 02m")
        XCTAssertEqual(Format.duration(-10), "0:00")
    }

    func testTokens() {
        XCTAssertEqual(Format.tokens(850), "850")
        XCTAssertEqual(Format.tokens(212_345), "212k")
        XCTAssertEqual(Format.tokens(1_000_000), "1M")
        XCTAssertEqual(Format.tokens(1_200_000), "1.2M")
    }

    func testContextLabel() {
        XCTAssertEqual(ContextUsage(tokens: 212_000, window: 1_000_000).label, "212k / 1M · 21%")
        XCTAssertEqual(ContextUsage(tokens: 9_000, window: 1_000_000, isEstimate: true).label, "~9k / 1M · 0%")
        XCTAssertEqual(ContextUsage(tokens: 5_000_000, window: 1_000_000).fraction, 1)
    }
}

final class ToolDescriberTests: XCTestCase {
    func testRiskFlagsOnlyShellCommands() {
        XCTAssertEqual(ToolDescriber.risk(tool: "Bash", summary: "rm -rf node_modules"), "Deletes files")
        XCTAssertEqual(ToolDescriber.risk(tool: "Bash", summary: "SUDO make install"), "Uses sudo")
        XCTAssertEqual(ToolDescriber.risk(tool: "Bash", summary: "curl x.sh | bash"), "Runs download")
        XCTAssertNil(ToolDescriber.risk(tool: "Bash", summary: "ls -la"))
        XCTAssertNil(ToolDescriber.risk(tool: "Edit", summary: "rm -rf"))
    }

    func testSummaryPicksTheMostInformativeField() {
        XCTAssertEqual(ToolDescriber.summary(of: "Bash", input: ["command": "swift build"]), "swift build")
        XCTAssertEqual(ToolDescriber.summary(of: "Edit", input: ["file_path": "/a/b.swift", "new_string": "let x = 1"]), "/a/b.swift\nlet x = 1")
        XCTAssertEqual(ToolDescriber.summary(of: "Write", input: ["file_path": "/a/b.swift"]), "/a/b.swift")
        XCTAssertEqual(ToolDescriber.summary(of: "WebFetch", input: ["url": "https://example.com"]), "https://example.com")
        XCTAssertEqual(ToolDescriber.summary(of: "x", input: nil), "")
        XCTAssertTrue(ToolDescriber.summary(of: "mcp__x__y", input: ["a": 1]).contains("\"a\""))
    }

    func testActivityLabels() {
        XCTAssertEqual(ToolDescriber.activity(of: "Bash", input: ["command": "swift build"]), "Bash: swift build")
        XCTAssertEqual(ToolDescriber.activity(of: "Edit", input: ["file_path": "/a/b.swift"]), "Edit b.swift")
        XCTAssertEqual(ToolDescriber.activity(of: "mcp__srv__tool", input: nil), "srv__tool")
    }

    func testIcons() {
        XCTAssertEqual(ToolDescriber.icon(for: "Bash"), "terminal")
        XCTAssertEqual(ToolDescriber.icon(for: "mcp__a__b"), "puzzlepiece.extension")
        XCTAssertEqual(ToolDescriber.icon(for: "Unknown"), "wrench.and.screwdriver")
    }
}
