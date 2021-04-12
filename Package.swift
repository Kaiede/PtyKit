// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PTYKit",
    products: [
        .library(
            name: "PTYKit",
            targets: ["PTYKit"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PTYKit",
            dependencies: ["CPTYKit"]),
        .target(name: "CPTYKit")
    ]
)
