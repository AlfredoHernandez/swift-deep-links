//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

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
}
