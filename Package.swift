// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FSUserStories",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "FSUserStories",
            targets: ["FSUserStoriesApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "FSUserStoriesApp",
            path: "Sources/FSUserStoriesApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "FSUserStoriesAppTests",
            dependencies: ["FSUserStoriesApp"],
            path: "Tests/FSUserStoriesAppTests"
        )
    ]
)
