// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GGGMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GGGMacCore", targets: ["GGGMacCore"]),
        .executable(name: "GGGMac", targets: ["GGGMac"])
    ],
    targets: [
        .target(name: "GGGMacCore", resources: [.copy("Resources/GGGMacGraphicsProbe.exe")]),
        .executableTarget(name: "GGGMac", dependencies: ["GGGMacCore"]),
        .testTarget(name: "GGGMacCoreTests", dependencies: ["GGGMacCore"])
    ]
)
