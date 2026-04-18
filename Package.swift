// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MouseBoost",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "mouseboost", targets: ["MouseBoost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "MouseBoost",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
