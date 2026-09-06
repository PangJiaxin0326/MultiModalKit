// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MultiModalKit",
    platforms: [
        .iOS("26.0"),
        .macOS("27.0"),
        .visionOS("27.0"),
    ],
    products: [
        .library(
            name: "MultiModalKit",
            targets: ["MultiModalKit"]
        ),
    ],
    // No AIToolKit dependency: the AIToolKit-backed tools that needed it now live in the
    // separate, strictly-iOS-27 MultiModalAITools package. Keeping MultiModalKit free of
    // AIToolKit is what lets it stay at the iOS 26 floor (and keeps the iOS-27-only
    // FoundationModels symbols out of iOS-26 hosts like the Red app).
    targets: [
        .target(
            name: "MultiModalKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MultiModalKitTests",
            dependencies: [
                "MultiModalKit",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
