// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RimeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RimeKit", targets: ["RimeKit"]),
    ],
    targets: [
        // Built by Scripts/fetch-librime.sh from the official librime release.
        // RimeKit is the only module allowed to import it.
        .binaryTarget(name: "librime", path: "../../Frameworks/librime.xcframework"),
        .target(name: "RimeKit", dependencies: ["librime"]),
        .testTarget(name: "RimeKitTests", dependencies: ["RimeKit", "librime"]),
    ]
)
