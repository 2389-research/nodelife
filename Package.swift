// ABOUTME: Root Package.swift for the merged NodeLife project
// ABOUTME: Defines the SwiftUI app target and depends on local NodeLifeCore package

// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NodeLife",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "NodeLifeCore",
            targets: ["NodeLifeCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "NodeLife",
            dependencies: [
                "NodeLifeCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/NodeLife",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .target(
            name: "NodeLifeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "NodeLifeCore/Sources/NodeLifeCore",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "NodeLifeCoreTests",
            dependencies: ["NodeLifeCore"],
            path: "NodeLifeCore/Tests/NodeLifeCoreTests",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
