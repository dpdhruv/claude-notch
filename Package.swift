// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeNotch", targets: ["ClaudeNotch"]),
    ],
    targets: [
        // Everything that isn't UI: transcript parsing, state inference, hooks, permission bridge.
        .target(name: "NotchCore"),
        // The menu-bar-less app: a SwiftUI panel wrapped around the notch.
        .executableTarget(name: "ClaudeNotch", dependencies: ["NotchCore"]),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
    ]
)
