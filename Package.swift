// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CleanShotZ",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "CleanShotZ",
            path: "Sources/CleanShotZ"
        ),
    ]
)
