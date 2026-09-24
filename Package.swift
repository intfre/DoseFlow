// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DoseFlow",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "DoseFlowCore", targets: ["DoseFlowCore"])
    ],
    targets: [
        .target(name: "DoseFlowCore"),
        .testTarget(
            name: "DoseFlowCoreTests",
            dependencies: ["DoseFlowCore"]
        )
    ]
)
