// swift-tools-version: 6.0
import PackageDescription

// Release tooling: checks tags, extracts release notes, writes and verifies
// the Sparkle appcast. Runs on the build machine only, never in the app.
let package = Package(
    name: "scribe-release",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "scribe-release", targets: ["scribe-release"]),
    ],
    targets: [
        .target(name: "ReleaseKit"),
        .executableTarget(name: "scribe-release", dependencies: ["ReleaseKit"]),
        .testTarget(name: "ReleaseKitTests", dependencies: ["ReleaseKit"]),
    ]
)
