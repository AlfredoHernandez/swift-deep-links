// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-deep-link",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "DeepLink", targets: ["DeepLink"]),
    ],
    targets: [
        .target(name: "DeepLink"),
        .testTarget(name: "DeepLinkTests", dependencies: ["DeepLink"]),
    ],
)
