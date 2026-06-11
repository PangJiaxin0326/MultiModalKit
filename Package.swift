// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MultiModalKit",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        .library(
            name: "MultiModalKit",
            targets: ["MultiModalKit"]
        ),
    ],
    dependencies: [
        .package(path: "../AIToolKit"),
    ],
    targets: [
        .target(
            name: "MultiModalKit",
            dependencies: [
                .product(name: "AIToolKit", package: "AIToolKit"),
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MultiModalKitTests",
            dependencies: [
                "MultiModalKit",
                .product(name: "AIToolKit", package: "AIToolKit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
