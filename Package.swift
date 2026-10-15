// swift-tools-version: 6.2

import PackageDescription

let package = Package(
	name: "swift-deep-links",
	// Apple platforms only: the library uses `os` (Logger, OSAllocatedUnfairLock, signposts) unconditionally.
	platforms: [
		.iOS(.v16),
		.macOS(.v13),
		.tvOS(.v16),
		.watchOS(.v9),
		.visionOS(.v1),
	],
	products: [
		.library(name: "DeepLinks", targets: ["DeepLinks"]),
		.library(name: "DeepLinksTesting", targets: ["DeepLinksTesting"]),
	],
	targets: [
		.target(name: "DeepLinks"),
		.target(name: "DeepLinksTesting", dependencies: ["DeepLinks"]),
		.testTarget(name: "DeepLinksTests", dependencies: ["DeepLinks", "DeepLinksTesting"]),
		.testTarget(name: "DeepLinksTestingTests", dependencies: ["DeepLinks", "DeepLinksTesting"]),
	],
)
