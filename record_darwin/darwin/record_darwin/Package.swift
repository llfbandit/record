// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "record_darwin",
    platforms: [
        .iOS("12.0"),
        .macOS("10.15")
    ],
    products: [
        // If the plugin name contains "_", replace with "-" for the library name.
        .library(name: "record-darwin", targets: ["record_darwin"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "record_darwin",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
