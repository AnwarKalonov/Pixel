// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Pixel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pixel", targets: ["Pixel"])
    ],
    targets: [
        .executableTarget(
            name: "Pixel",
            path: "Sources/Pixel",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
