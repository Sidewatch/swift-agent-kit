// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentStatus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentStatus", targets: ["AgentStatus"]),
    ],
    targets: [
        .target(name: "AgentStatus", resources: [.process("Localizable.xcstrings")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentStatusTests", dependencies: ["AgentStatus"]),
    ]
)
