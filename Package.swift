// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flactastic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "flactastic"
        ),
        .testTarget(
            name: "flactasticTests",
            dependencies: ["flactastic"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
