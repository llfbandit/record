// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "record_ios",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        // If the plugin name contains "_", replace with "-" for the library name.
        .library(name: "record-ios", targets: ["record_ios"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "record_ios",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)