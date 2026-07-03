// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftRouter",
    platforms: [
        .iOS(.v15),
        // macOS exists solely so the pure-logic suite runs via `swift test`.
        .macOS(.v13),
    ],
    products: [
        .library(name: "SwiftRouter", targets: ["SwiftRouter"])
    ],
    targets: [
        .target(name: "SwiftRouter"),
        .testTarget(name: "SwiftRouterTests", dependencies: ["SwiftRouter"]),
    ]
)
