//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct CompositionTests {
	// MARK: - Delegate Composition Tests

	@Test
	@MainActor func `compose with variadic delegates creates composite delegate`() {
		let provider = DefaultAnalyticsProvider()

		let composite = compose(
			.logging(),
			.analytics(provider: provider),
			.notification(),
		)

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test
	@MainActor func `compose with array of delegates creates composite delegate`() {
		let provider = DefaultAnalyticsProvider()

		let delegates: [DeepLinkCoordinatorDelegate] = [
			.logging(),
			.analytics(provider: provider),
			.notification(),
		]

		let composite = compose(delegates)

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test
	@MainActor func `composed delegate executes all delegates in order`() throws {
		let spy1 = DelegateSpy()
		let spy2 = DelegateSpy()
		let spy3 = DelegateSpy()

		let composite = compose(spy1, spy2, spy3)

		let url = try #require(URL(string: "test://example"))
		let dummyCoordinator = DummyCoordinator()
		composite.coordinator(dummyCoordinator, willProcess: url)

		#expect(spy1.willProcessCalled == true)
		#expect(spy2.willProcessCalled == true)
		#expect(spy3.willProcessCalled == true)
	}

	@Test
	@MainActor func `composed delegate works with coordinator`() async throws {
		let provider = DefaultAnalyticsProvider()
		let routing = TestRouting()
		let handler = TestHandler()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(handler)
			.delegate(compose(
				.logging(),
				.analytics(provider: provider),
			))
			.build()

		let url = try #require(URL(string: "test://example"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes.count == 1)
	}

	// MARK: - Middleware Composition Tests

	@Test
	func `compose with variadic middleware creates array`() {
		let provider = DefaultAnalyticsProvider()

		let middleware = compose(
			.logging(),
			.analytics(provider: provider),
			.rateLimit(maxRequests: 10, timeWindow: 60),
		)

		#expect(middleware.count == 3)
		#expect(middleware[0] is LoggingMiddleware)
		#expect(middleware[1] is AnalyticsMiddleware)
		#expect(middleware[2] is RateLimitMiddleware)
	}

	@Test
	func `compose with array of middleware returns same array`() {
		let provider = DefaultAnalyticsProvider()

		let middlewareList: [any DeepLinkMiddleware] = [
			.logging(),
			.analytics(provider: provider),
		]

		let composed = compose(middlewareList)

		#expect(composed.count == 2)
		#expect(composed[0] is LoggingMiddleware)
		#expect(composed[1] is AnalyticsMiddleware)
	}

	@Test
	func `composed middleware works with coordinator builder`() async throws {
		let provider = DefaultAnalyticsProvider()
		let routing = TestRouting()
		let handler = TestHandler()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(handler)
			.middleware(compose(
				.logging(),
				.analytics(provider: provider),
				.rateLimit(maxRequests: 10, timeWindow: 60),
			))
			.build()

		let url = try #require(URL(string: "test://example"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes.count == 1)
	}

	@Test
	@MainActor func `compose with single delegate works correctly`() {
		let composite = compose(.logging())

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test
	func `compose middleware with single item works correctly`() {
		let middleware: [any DeepLinkMiddleware] = compose(.logging())

		#expect(middleware.count == 1)
		#expect(middleware[0] is LoggingMiddleware)
	}

	@Test
	@MainActor func `compose with empty array creates empty composite`() throws {
		let delegates: [DeepLinkCoordinatorDelegate] = []
		let composite = compose(delegates)

		#expect(composite is CompositeDeepLinkDelegate)

		// Should not crash when calling methods
		let url = try #require(URL(string: "test://example"))
		let dummyCoordinator = DummyCoordinator()
		composite.coordinator(dummyCoordinator, willProcess: url)
	}

	// MARK: - Test Helpers

	enum TestRoute: DeepLinkRoute {
		case test

		var id: String {
			"test"
		}
	}

	struct TestRouting: DeepLinkRouting {
		func route(from _: URL) async throws -> [TestRoute] {
			[.test]
		}
	}

	struct TestHandler: DeepLinkHandler {
		func handle(_: TestRoute) async throws {}
	}

	final class DummyCoordinator {}

	final class DelegateSpy: DeepLinkCoordinatorDelegate, @unchecked Sendable {
		var willProcessCalled = false
		var didProcessCalled = false
		var didFailProcessingCalled = false

		func coordinator(_: AnyObject, willProcess _: URL) {
			willProcessCalled = true
		}

		func coordinator(_: AnyObject, didProcess _: URL, result _: DeepLinkResultProtocol) {
			didProcessCalled = true
		}

		func coordinator(_: AnyObject, didFailProcessing _: URL, error _: Error) {
			didFailProcessingCalled = true
		}
	}
}
