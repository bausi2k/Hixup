// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hixup",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "HixupCore", targets: ["HixupCore"])
    ],
    targets: [
        .target(name: "HixupCore"),
        .testTarget(name: "HixupCoreTests", dependencies: ["HixupCore"])
    ]
)
