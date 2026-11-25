// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hixup",
    defaultLocalization: "de",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "HixupCore", targets: ["HixupCore"])
    ],
    targets: [
        .target(name: "HixupCore", resources: [.process("Resources")]),
        .testTarget(name: "HixupCoreTests", dependencies: ["HixupCore"])
    ]
)
