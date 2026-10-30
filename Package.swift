// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sw33p",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Sw33pCore", targets: ["Sw33pCore"]),
        .executable(name: "sw33p", targets: ["Sw33pApp"]),
    ],
    targets: [
        .target(
            name: "Sw33pCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Sw33pApp",
            dependencies: ["Sw33pCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "Sw33pCoreTests",
            dependencies: ["Sw33pCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "Sw33pAppTests",
            dependencies: ["Sw33pApp"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
