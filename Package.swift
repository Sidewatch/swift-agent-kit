// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentSession",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentSession", targets: ["AgentSession"]),
    ],
    dependencies: [
        .package(path: "../swift-process-runner"),
        .package(path: "../swift-foundation-extensions"),
    ],
    targets: [
        .target(name: "AgentSession", dependencies: [.product(name: "ProcessRunner", package: "swift-process-runner"), .product(name: "FoundationExtensions", package: "swift-foundation-extensions")], path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "AgentSessionTests", dependencies: ["AgentSession"], path: "Tests"),
    ]
)
