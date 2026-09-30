// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ColorCapture",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ColorCapture", path: "Sources/ColorCapture")
    ]
)
