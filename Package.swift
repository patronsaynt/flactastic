// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flactastic",
    platforms: [.macOS(.v14)],
    targets: [
        // TagLib C API — discovered via `pkg-config taglib_c` (requires `brew install taglib`).
        .systemLibrary(
            name: "CTagLib",
            pkgConfig: "taglib_c",
            providers: [.brew(["taglib"])]
        ),
        // Thin C bridge exposing the TAGLIB_COMPLEX_PROPERTY_PICTURE macro as a
        // plain C function callable from Swift (Swift cannot expand C macros directly).
        .target(
            name: "CTagLibHelper",
            dependencies: ["CTagLib"],
            path: "Sources/CTagLibHelper",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "flactastic",
            dependencies: ["CTagLibHelper"],
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources/Wordmark.png"),
            ]
        ),
        .testTarget(
            name: "flactasticTests",
            dependencies: ["flactastic"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
