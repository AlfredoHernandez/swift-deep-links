//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Testing

struct CollectingHandlerTests {
	@Test
	func `starts with no handled routes`() {
		let sut = CollectingHandler<TestRoute>()

		#expect(sut.handledRoutes.isEmpty)
	}

	@Test
	func `collects handled routes in order`() async throws {
		let sut = CollectingHandler<TestRoute>()

		try await sut.handle(.routeA)
		try await sut.handle(.routeB)
		try await sut.handle(.routeA)

		#expect(sut.handledRoutes == [.routeA, .routeB, .routeA])
	}

	@Test
	func `is thread-safe under concurrent access`() async {
		let sut = CollectingHandler<TestRoute>()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 100 {
				group.addTask { try? await sut.handle(.routeA) }
			}
		}

		#expect(sut.handledRoutes.count == 100)
	}

	@Test
	func `records the context of each route`() async throws {
		let sut = CollectingHandler<TestRoute>()
		let context = DeepLinkContext(source: .notification, sceneID: "scene-1")

		try await sut.handle(.routeA, context: context)
		try await sut.handle(.routeB)

		#expect(sut.handledRoutes == [.routeA, .routeB])
		#expect(sut.handledContexts == [context, .unknown])
	}
}
