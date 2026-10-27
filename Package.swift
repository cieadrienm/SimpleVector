// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleVector",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimpleVectorCore", targets: ["SimpleVectorCore"]),
        .library(name: "SimpleVectorMCPCore", targets: ["SimpleVectorMCPCore"]),
        .executable(name: "SimpleVector", targets: ["SimpleVector"]),
        .executable(name: "simplevector-mcp", targets: ["simplevector-mcp"]),
    ],
    targets: [
        .target(name: "SimpleVectorCore"),
        .executableTarget(name: "SimpleVector", dependencies: ["SimpleVectorCore"]),
        .target(name: "SimpleVectorMCPCore"),
        .executableTarget(name: "simplevector-mcp", dependencies: ["SimpleVectorMCPCore"]),
        .testTarget(name: "SimpleVectorCoreTests", dependencies: ["SimpleVectorCore"]),
        .testTarget(name: "SimpleVectorAppTests", dependencies: ["SimpleVector", "SimpleVectorCore", "SimpleVectorMCPCore"]),
    ],
    swiftLanguageModes: [.v5]
)
