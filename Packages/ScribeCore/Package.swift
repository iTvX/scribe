// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScribeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScribeCore", targets: ["ScribeCore"]),
    ],
    dependencies: [
        .package(path: "../RimeKit"),
        .package(path: "../ScribeConfig"),
    ],
    targets: [
        .target(name: "ScribeCore", dependencies: ["RimeKit", "ScribeConfig"]),
        .testTarget(name: "ScribeCoreTests", dependencies: ["ScribeCore"]),
    ]
)
