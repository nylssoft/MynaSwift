// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MynaSwift",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MynaSwift", targets: ["MynaSwift"])
    ],
    targets: [
        .executableTarget(
            name: "MynaSwift",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
