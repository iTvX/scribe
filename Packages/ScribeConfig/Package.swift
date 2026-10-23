// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScribeConfig",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScribeConfig", targets: ["ScribeConfig"]),
    ],
    dependencies: [
        .package(path: "../RimeKit"),
    ],
    targets: [
        .target(name: "ScribeConfig", dependencies: ["RimeKit"]),
        .testTarget(name: "ScribeConfigTests", dependencies: ["ScribeConfig"]),
    ]
)
