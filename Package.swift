// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pasty",
    platforms: [
        .macOS(.v13),
    ],
    targets: [
        .target(
            name: "PastyCore"
        ),
        .executableTarget(
            name: "Pasty",
            dependencies: ["PastyCore"]
        ),
        .executableTarget(
            name: "PastyTests",
            dependencies: ["PastyCore"]
        ),
    ]
)
