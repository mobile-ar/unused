// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "unused",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "unused", targets: ["unused"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2")
    ],
    targets: [
        .executableTarget(
            name: "unused",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "unusedTests", dependencies: ["unused"]),
    ]
)
