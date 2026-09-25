// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThumbGestures",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ThumbGesturesCore"),
        .executableTarget(name: "ThumbGestures", dependencies: ["ThumbGesturesCore"]),
        .testTarget(name: "ThumbGesturesCoreTests", dependencies: ["ThumbGesturesCore"]),
    ]
)
