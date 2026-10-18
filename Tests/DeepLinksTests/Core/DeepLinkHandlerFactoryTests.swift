//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct DeepLinkHandlerFactoryTests {
	@Test
	func `from produces a handler that forwards routes to the closure`() async throws {
		let collector = CollectingHandler<TestRoute>()
		let handler: any DeepLinkHandler<TestRoute> = .from { route in
			try await collector.handle(route)
		}

		try await handler.handle(.route1)
		try await handler.handle(.route2)

		#expect(collector.handledRoutes == [.route1, .route2])
	}

	@Test
	func `from forwards the exact error thrown from the closure`() async {
		let handler: any DeepLinkHandler<TestRoute> = .from { _ in
			throw DeepLinkError.handlerError(message: "boom", underlyingError: nil)
		}

		await #expect(throws: DeepLinkError.handlerError(message: "boom", underlyingError: nil)) {
			try await handler.handle(.route1)
		}
	}

	@Test
	func `from integrates with the coordinator builder using dot-shorthand`() async throws {
		let collector = CollectingHandler<TestRoute>()
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		routingStub.routesToReturn = [.route1]

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(.from { route in try await collector.handle(route) })
			.build()

		let url = try #require(URL(string: "test://handler"))
		_ = await coordinator.handle(url: url)

		#expect(collector.handledRoutes == [.route1])
	}

	@Test
	func `from handler is safe to invoke concurrently from multiple tasks`() async throws {
		let collector = CollectingHandler<TestRoute>()
		let handler: any DeepLinkHandler<TestRoute> = .from { route in
			try await collector.handle(route)
		}

		// 64 concurrent invocations stress the Sendable boxing hard enough
		// that a future regression dropping @Sendable on the closure would
		// surface as a lost-or-duplicated route, not merely a fencing pass.
		let routes: [TestRoute] = Array(repeating: [.route1, .route2, .route3], count: 22).flatMap(\.self).prefix(64).map(\.self)

		try await withThrowingTaskGroup(of: Void.self) { group in
			for route in routes {
				group.addTask {
					try await handler.handle(route)
				}
			}
			try await group.waitForAll()
		}

		#expect(collector.handledRoutes.sorted(by: { $0.id < $1.id }) == routes.sorted(by: { $0.id < $1.id }))
	}
}
