// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDiag",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MacDiagCore", targets: ["MacDiagCore"])
    ],
    targets: [
        .target(name: "MacDiagCore"),
        .testTarget(name: "MacDiagCoreTests", dependencies: ["MacDiagCore"])
    ]
)
