// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LyricsKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "LyricsKit",
            targets: ["LyricsKit"]
        ),
    ],
    targets: [
        .target(name: "LyricsKit"),
        .testTarget(
            name: "LyricsKitTests",
            dependencies: ["LyricsKit"]
        ),
    ]
)
