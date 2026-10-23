// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScribeUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScribeUI", targets: ["ScribeUI"]),
    ],
    dependencies: [
        .package(path: "../ScribeConfig"),
        .package(path: "../ScribeCore"),
    ],
    targets: [
        .target(name: "ScribeUI", dependencies: ["ScribeConfig", "ScribeCore"]),
        .testTarget(name: "ScribeUITests", dependencies: ["ScribeUI", "ScribeConfig", "ScribeCore"]),
    ]
)
