// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Listen Here",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Listen Here",
            targets: ["Listen Here"]
        ),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Listen Here",
            dependencies: []
        ),
    ]
)