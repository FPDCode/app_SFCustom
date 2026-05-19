// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SFCustomApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SFCustomApp", targets: ["SFCustomApp"])
    ],
    targets: [
        .executableTarget(
            name: "SFCustomApp",
            path: "Sources/SFCustomApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
