// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "OliveMail",
    products: [
        .executable(name: "olive-mail",
                    targets: ["OliveMail"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser",
                 exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-system",
                 exact: "1.8.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "OliveMail",
            dependencies: [
                .product(name: "ArgumentParser",
                         package: "swift-argument-parser"),
                .product(name: "SystemPackage",
                         package: "swift-system"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "OliveMailTests",
            dependencies: [
                "OliveMail",
                .product(name: "ArgumentParser",
                         package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
