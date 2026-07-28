// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "bibi",
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "bibi",
            targets: ["bibi"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
    ],
    targets: [
        .target(
            name: "bibi",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
