// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MultiModalKit",
    platforms: [
        .iOS("26.5"),
        .macOS("26.5"),
        .visionOS("26.5"),
    ],
    products: [
        .library(
            name: "MultiModalKit",
            targets: ["MultiModalKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/PangJiaxin0326/AIToolKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "MultiModalKit",
            dependencies: [
                .product(name: "AIToolKit", package: "AIToolKit"),
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
