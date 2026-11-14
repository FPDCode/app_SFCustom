// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SFCustomApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SFCustomApp", targets: ["SFCustomApp"]),
        .library(name: "SFCustomEngine", targets: ["SFCustomEngine"]),
        .executable(name: "sfcustom", targets: ["sfcustom"]),
    ],
    targets: [
        // UI-free geometry engine: SVG parsing, compatible stroke outlining,
        // interpolation checks. Builds on macOS and Linux (CI / CLI).
        .target(
            name: "SFCustomEngine",
            path: "Sources/SFCustomEngine"
        ),
        .executableTarget(
            name: "SFCustomApp",
            dependencies: ["SFCustomEngine"],
            path: "Sources/SFCustomApp",
            resources: [
                .process("Resources")
            ]
        ),
        // Command-line front end for CI: export / lint / font.
        .executableTarget(
            name: "sfcustom",
            dependencies: ["SFCustomEngine"],
            path: "Sources/sfcustom"
        ),
        .testTarget(
            name: "SFCustomEngineTests",
            dependencies: ["SFCustomEngine"],
            path: "Tests/SFCustomEngineTests"
        ),
    ]
)
