//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct SceneRoutingHandlerTests {
	@Test
	func `each link reaches only the scene it came from`() async {
		let scenes = TwoScenes()

		_ = await scenes.coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(source: .customScheme, sceneID: "scene-A"))
		_ = await scenes.coordinator.handle(url: url("myapp://b"), context: DeepLinkContext(source: .universalLink, sceneID: "scene-B"))

		#expect(scenes.sceneA.handledRoutes == [.route1])
		#expect(scenes.sceneB.handledRoutes == [.route1])
		#expect(scenes.sceneA.handledContexts.map(\.sceneID) == ["scene-A"])
		#expect(scenes.sceneB.handledContexts.map(\.sceneID) == ["scene-B"])
	}

	@Test
	func `scene handler receives the full context`() async {
		let scenes = TwoScenes()
		let context = DeepLinkContext(source: .notification, sourceApplication: "com.other", sceneID: "scene-A")

		_ = await scenes.coordinator.handle(url: url("myapp://a"), context: context)

		#expect(scenes.sceneA.handledContexts == [context])
	}

	@Test
	func `link without a scene goes to the fallback`() async {
		let scenes = TwoScenes()

		_ = await scenes.coordinator.handle(url: url("myapp://a"))

		#expect(scenes.fallback.handledRoutes == [.route1])
		#expect(scenes.sceneA.handledRoutes.isEmpty)
		#expect(scenes.sceneB.handledRoutes.isEmpty)
	}

	@Test
	func `link from an unregistered scene goes to the fallback`() async {
		let scenes = TwoScenes()

		_ = await scenes.coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(sceneID: "closed-scene"))

		#expect(scenes.fallback.handledRoutes == [.route1])
	}

	@Test
	func `unregistered scene stops receiving links`() async {
		let scenes = TwoScenes()

		scenes.router.unregister(scene: "scene-A")
		_ = await scenes.coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(sceneID: "scene-A"))

		#expect(scenes.sceneA.handledRoutes.isEmpty)
		#expect(scenes.fallback.handledRoutes == [.route1])
	}

	@Test
	func `registering a scene again replaces its handler`() async {
		let scenes = TwoScenes()
		let replacement = CollectingHandler<TestRoute>()

		scenes.router.register(replacement, forScene: "scene-A")
		_ = await scenes.coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(sceneID: "scene-A"))

		#expect(scenes.sceneA.handledRoutes.isEmpty)
		#expect(replacement.handledRoutes == [.route1])
	}

	@Test
	func `without a fallback an unroutable link fails the route`() async {
		let router = SceneRoutingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: router)

		let result = await coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(sceneID: "scene-A"))

		#expect(result.failedRoutes == 1)
		#expect(result.firstDeepLinkError == .handlerError(message: SceneRoutingHandler<TestRoute>.noSceneHandlerMessage, underlyingError: nil))
	}

	@Test
	func `registered scene IDs are reported`() {
		let scenes = TwoScenes()

		#expect(scenes.router.registeredSceneIDs == ["scene-A", "scene-B"])
	}
}

// MARK: - Helpers

private struct TwoScenes {
	let sceneA = CollectingHandler<TestRoute>()
	let sceneB = CollectingHandler<TestRoute>()
	let fallback = CollectingHandler<TestRoute>()
	let router: SceneRoutingHandler<TestRoute>
	let coordinator: DeepLinkCoordinator<TestRoute>

	init() {
		router = SceneRoutingHandler(fallback: fallback)
		router.register(sceneA, forScene: "scene-A")
		router.register(sceneB, forScene: "scene-B")
		coordinator = makeCoordinator(handler: router)
	}
}

private func makeCoordinator(handler: some DeepLinkHandler<TestRoute>) -> DeepLinkCoordinator<TestRoute> {
	DeepLinkCoordinator(routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]), handler: handler)
}

private func url(_ string: String) -> URL {
	URL(string: string)!
}
