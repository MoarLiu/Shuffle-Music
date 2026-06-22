// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShuffleMusic",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ShuffleMusic", targets: ["ShuffleMusic"]),
        .executable(name: "ShuffleMusicCoreTests", targets: ["ShuffleMusicCoreTests"])
    ],
    targets: [
        .target(
            name: "ShuffleMusicCore",
            path: "Sources/ShuffleMusicCore"
        ),
        .executableTarget(
            name: "ShuffleMusic",
            dependencies: ["ShuffleMusicCore"],
            path: "Sources/ShuffleMusic",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Combine"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "ShuffleMusicCoreTests",
            dependencies: ["ShuffleMusicCore"],
            path: "Tests/ShuffleMusicCoreTests"
        )
    ]
)
