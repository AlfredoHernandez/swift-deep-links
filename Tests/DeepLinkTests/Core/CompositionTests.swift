//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("Functional Composition Tests")
struct CompositionTests {
	// MARK: - Delegate Composition Tests

	@Test("compose with variadic delegates creates composite delegate")
	@MainActor func compose_withVariadicDelegates_createsCompositeDelegate() {
		let provider = DefaultAnalyticsProvider()

		let composite = compose(
			.logging(),
			.analytics(provider: provider),
			.notification(),
		)

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test("compose with array of delegates creates composite delegate")
	@MainActor func compose_withArrayOfDelegates_createsCompositeDelegate() {
		let provider = DefaultAnalyticsProvider()

		let delegates: [DeepLinkCoordinatorDelegate] = [
			.logging(),
			.analytics(provider: provider),
			.notification(),
		]

		let composite = compose(delegates)

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test("composed delegate executes all delegates in order")
	@MainActor func composedDelegate_executesAllDelegatesInOrder() throws {
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

	@Test("composed delegate works with coordinator")
	@MainActor func composedDelegate_worksWithCoordinator() async throws {
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

	@Test("compose with variadic middleware creates array")
	func compose_withVariadicMiddleware_createsArray() {
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

	@Test("compose with array of middleware returns same array")
	func compose_withArrayOfMiddleware_returnsSameArray() {
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

	@Test("composed middleware works with coordinator builder")
	func composedMiddleware_worksWithCoordinatorBuilder() async throws {
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

	@Test("compose with single delegate works correctly")
	@MainActor func compose_withSingleDelegate_worksCorrectly() {
		let composite = compose(.logging())

		#expect(composite is CompositeDeepLinkDelegate)
	}

	@Test("compose middleware with single item works correctly")
	func composeMiddleware_withSingleItem_worksCorrectly() {
		let middleware: [any DeepLinkMiddleware] = compose(.logging())

		#expect(middleware.count == 1)
		#expect(middleware[0] is LoggingMiddleware)
	}

	@Test("compose with empty array creates empty composite")
	@MainActor func compose_withEmptyArray_createsEmptyComposite() throws {
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
