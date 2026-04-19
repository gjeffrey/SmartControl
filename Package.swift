// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SmartControl",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "SmartControl", targets: ["SmartControl"]),
    ],
    targets: [
        .executableTarget(
            name: "SmartControl",
            path: "Sources/SmartControl"
        ),
    ]
)
