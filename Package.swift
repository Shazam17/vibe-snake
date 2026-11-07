// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Snake",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SnakeKit", path: "Sources/SnakeKit"),
        .executableTarget(name: "SnakeApp", dependencies: ["SnakeKit"], path: "Sources/SnakeApp"),
        .testTarget(name: "SnakeKitTests", dependencies: ["SnakeKit"], path: "Tests/SnakeKitTests")
    ]
)
