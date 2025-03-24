// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "record_macos",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        // If the plugin name contains "_", replace with "-" for the library name.
        .library(name: "record-macos", targets: ["record_macos"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "record_macos",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)