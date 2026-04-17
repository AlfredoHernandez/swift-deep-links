// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "swift-deep-links",
	platforms: [
		.iOS(.v16),
		.macOS(.v13),
	],
	products: [
		.library(name: "DeepLinks", targets: ["DeepLinks"]),
		.library(name: "DeepLinksTesting", targets: ["DeepLinksTesting"]),
	],
	targets: [
		.target(name: "DeepLinks"),
		.target(name: "DeepLinksTesting", dependencies: ["DeepLinks"]),
		.testTarget(name: "DeepLinksTests", dependencies: ["DeepLinks"]),
		.testTarget(name: "DeepLinksTestingTests", dependencies: ["DeepLinks", "DeepLinksTesting"]),
	],
)
