// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-agent-kit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentSession", targets: ["AgentSession"]),
        .library(name: "AgentStatus", targets: ["AgentStatus"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions")
    ],
    targets: [
        .target(
            name: "AgentSession",
            dependencies: [
                .product(name: "ProcessRunner", package: "swift-foundation-extensions"),
                .product(name: "FoundationExtensions", package: "swift-foundation-extensions"),
            ],
            resources: [.process("Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(
            name: "AgentStatus", dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions")],
            resources: [.process("Localizable.xcstrings")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentSessionTests", dependencies: ["AgentSession", "AgentStatus"], resources: [.copy("Fixtures")]),
        .testTarget(name: "AgentStatusTests", dependencies: ["AgentStatus"]),
    ]
)
