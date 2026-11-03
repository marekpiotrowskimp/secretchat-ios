// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GemmaKit",
    defaultLocalization: "pl",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GemmaKit", targets: ["GemmaKit"]),
    ],
    targets: [
        // Fetched by scripts/bootstrap.sh (official llama.cpp release, see PLAN.md).
        .binaryTarget(name: "llama", path: "Frameworks/llama.xcframework"),
        .target(
            name: "GemmaKit",
            dependencies: ["llama"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GemmaKitTests",
            dependencies: ["GemmaKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
