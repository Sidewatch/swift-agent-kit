// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentStatus",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentStatus", targets: ["AgentStatus"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
    ],
    targets: [
        .target(name: "AgentStatus", dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions")], resources: [.process("Localizable.xcstrings")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentStatusTests", dependencies: ["AgentStatus"]),
    ]
)
