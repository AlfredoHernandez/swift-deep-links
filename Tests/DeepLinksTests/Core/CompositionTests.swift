//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct CompositionTests {
	// MARK: - Delegate Composition Tests

	@Test
	@MainActor func `composed delegate executes all delegates in order`() throws {
		let spy1 = DelegateSpy()
		let spy2 = DelegateSpy()
		let spy3 = DelegateSpy()

		let composite = compose(spy1, spy2, spy3)

		let url = try #require(URL(string: "test://example"))
		let coordinator = try makeTestCoordinator()
		composite.coordinator(coordinator, willProcess: url)

		#expect(spy1.willProcessCalled == true)
		#expect(spy2.willProcessCalled == true)
		#expect(spy3.willProcessCalled == true)
	}

	@Test
	@MainActor func `composed delegate from an array forwards events to each delegate`() throws {
		let spy1 = DelegateSpy()
		let spy2 = DelegateSpy()

		let delegates: [any DeepLinkCoordinatorDelegate<TestRoute>] = [spy1, spy2]
		let composite = compose(delegates)

		let url = try #require(URL(string: "test://example"))
		let coordinator = try makeTestCoordinator()
		composite.coordinator(coordinator, willProcess: url)

		#expect(spy1.willProcessCalled == true)
		#expect(spy2.willProcessCalled == true)
	}

	@Test
	@MainActor func `composed delegate works with coordinator`() async throws {
		let provider = DefaultAnalyticsProvider()
		let routing = TestRouting()
		let handler = TestHandler()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test
	@MainActor func `compose with a single delegate still forwards events`() throws {
		let spy = DelegateSpy()

		let composite = compose(spy)

		let url = try #require(URL(string: "test://example"))
		let coordinator = try makeTestCoordinator()
		composite.coordinator(coordinator, willProcess: url)

		#expect(spy.willProcessCalled == true)
	}

	@Test
	@MainActor func `compose with an empty array does not crash when invoked`() throws {
		let delegates: [any DeepLinkCoordinatorDelegate<TestRoute>] = []
		let composite = compose(delegates)

		let url = try #require(URL(string: "test://example"))
		let coordinator = try makeTestCoordinator()
		composite.coordinator(coordinator, willProcess: url)
	}

	// MARK: - Middleware Composition

	@Test
	func `middleware arrays passed through the builder run all middleware in order`() async throws {
		let provider = DefaultAnalyticsProvider()
		let routing = TestRouting()
		let handler = TestHandler()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(handler)
			.middleware([
				.logging(),
				.analytics(provider: provider),
				.rateLimit(maxRequests: 10, timeWindow: 60),
			])
			.build()

		let url = try #require(URL(string: "test://example"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes.count == 1)
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

	@MainActor
	final class DelegateSpy: DeepLinkCoordinatorDelegate {
		var willProcessCalled = false
		var didProcessCalled = false
		var didFailProcessingCalled = false

		func coordinator(_: DeepLinkCoordinator<TestRoute>, willProcess _: URL) {
			willProcessCalled = true
		}

		func coordinator(_: DeepLinkCoordinator<TestRoute>, didProcess _: URL, result _: DeepLinkResult<TestRoute>) {
			didProcessCalled = true
		}

		func coordinator(_: DeepLinkCoordinator<TestRoute>, didFailProcessing _: URL, error _: Error) {
			didFailProcessingCalled = true
		}
	}

	@MainActor
	private func makeTestCoordinator() throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(TestRouting())
			.handler(TestHandler())
			.build()
	}
}
