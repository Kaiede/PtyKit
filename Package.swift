// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PTYKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PTYKit",
            targets: ["PTYKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "PTYKit",
            dependencies: [
                "CPTYKit",
                .product(name: "Logging", package: "swift-log")
            ]),
        .testTarget(
            name: "PTYKitTests",
            dependencies: ["PTYKit"]),
        .target(name: "CPTYKit")
    ]
)
