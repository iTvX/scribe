// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScribeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScribeCore", targets: ["ScribeCore"]),
        // A fake engine and test fixtures, for tests of code built on ScribeCore.
        .library(name: "ScribeTestSupport", targets: ["ScribeTestSupport"]),
    ],
    dependencies: [
        .package(path: "../RimeKit"),
        .package(path: "../ScribeConfig"),
    ],
    targets: [
        .target(name: "ScribeCore", dependencies: ["RimeKit", "ScribeConfig"]),
        .target(name: "ScribeTestSupport", dependencies: ["ScribeCore", "RimeKit"]),
        .testTarget(name: "ScribeCoreTests", dependencies: ["ScribeCore", "ScribeTestSupport", "RimeKit"]),
    ]
)
