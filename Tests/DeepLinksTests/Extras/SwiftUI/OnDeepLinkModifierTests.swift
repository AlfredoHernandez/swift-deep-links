//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(SwiftUI)

@testable import DeepLinks
import Foundation
import SwiftUI
import Testing

@MainActor
struct OnDeepLinkModifierTests {
	@Test
	func `onDeepLink modifier can be applied to a view without crashing`() {
		let routing = DeepLinkRoutingStub<TestRoute>()
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)

		// Smoke test: constructing the modified view must not crash or require
		// side-effectful setup. Full end-to-end coverage of URL forwarding lives
		// in the NSUserActivity tests and `DeepLinkCoordinatorTests`.
		_ = EmptyView().onDeepLink(coordinator)
	}

	@Test
	func `onDeepLink accepts an optional coordinator and no-ops when nil`() {
		let absentCoordinator: DeepLinkCoordinator<TestRoute>? = nil
		_ = EmptyView().onDeepLink(absentCoordinator)

		let routing = DeepLinkRoutingStub<TestRoute>()
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let presentCoordinator: DeepLinkCoordinator<TestRoute>? = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
		)
		_ = EmptyView().onDeepLink(presentCoordinator)
	}

	@Test
	func `onDeepLink accepts a scene identifier`() {
		let coordinator = DeepLinkCoordinator(routing: DeepLinkRoutingStub<TestRoute>(), handler: DeepLinkHandlerSpy<TestRoute>())
		let optional: DeepLinkCoordinator<TestRoute>? = coordinator

		_ = EmptyView().onDeepLink(coordinator, sceneID: "scene-A")
		_ = EmptyView().onDeepLink(optional, sceneID: "scene-A")
	}

	@Test(arguments: [
		("myapp://a", "scene-A", DeepLinkContext(source: .customScheme, sceneID: "scene-A")),
		("https://example.com/a", "scene-B", DeepLinkContext(source: .unknown, sceneID: "scene-B")),
		("myapp://a", "", DeepLinkContext(source: .customScheme)),
	])
	func `opened URLs carry the view's scene identifier`(link: String, sceneID: String, expected: DeepLinkContext) throws {
		#expect(try DeepLinkSceneIdentifier.openedURLContext(for: #require(URL(string: link)), sceneID: sceneID) == expected)
	}

	@Test
	func `empty scene identifiers are treated as absent`() {
		#expect(DeepLinkSceneIdentifier.normalized("") == nil)
		#expect(DeepLinkSceneIdentifier.normalized(nil) == nil)
		#expect(DeepLinkSceneIdentifier.normalized("scene-A") == "scene-A")
	}
}

#endif
