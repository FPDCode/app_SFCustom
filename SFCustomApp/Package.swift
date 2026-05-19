// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SFCustomApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SFCustomApp", targets: ["SFCustomApp"])
    ],
    dependencies: [
        // SVG → CGPath conversion. Pure Swift, MIT-licensed.
        // Used as the parsing front-end so we don't keep maintaining our own.
        .package(url: "https://github.com/swhitty/SwiftDraw", from: "0.27.0")
    ],
    targets: [
        .executableTarget(
            name: "SFCustomApp",
            dependencies: [
                .product(name: "SwiftDraw", package: "SwiftDraw")
            ],
            path: "Sources"
        )
    ]
)
