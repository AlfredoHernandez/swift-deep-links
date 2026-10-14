//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@MainActor
struct DeepLinkCoordinatorBuilderTests {
	// MARK: - Basic Configuration Tests

	@Test
	func `build creates coordinator with required components`() throws {
		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.build()
	}

	@Test
	func `build throws error when routing is missing`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("routing")) {
			try DeepLinkCoordinatorBuilder<TestRoute>()
				.handler(DeepLinkHandlerSpy<TestRoute>())
				.build()
		}
	}

	@Test
	func `build throws error when handler is missing`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("handler")) {
			try DeepLinkCoordinatorBuilder<TestRoute>()
				.routing(DeepLinkRoutingStub<TestRoute>())
				.build()
		}
	}

	// MARK: - Middleware Configuration Tests

	@Test
	func `middleware adds single middleware to coordinator`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let middlewareSpy = MiddlewareSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(middlewareSpy)
			.build()

		let url = try #require(URL(string: "test://middleware"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	@Test
	func `middleware with variadic adds multiple middleware`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(spy1, spy2)
			.build()

		let url = try #require(URL(string: "test://multiple"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(spy1.requests.contains(url))
		#expect(spy2.requests.contains(url))
	}

	@Test
	func `middleware with array adds multiple middleware`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware([spy1, spy2])
			.build()

		let url = try #require(URL(string: "test://multiple"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(spy1.requests.contains(url))
		#expect(spy2.requests.contains(url))
	}

	// MARK: - Delegate Configuration Tests

	@Test
	func `delegate adds single delegate to coordinator`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let delegateSpy = CoordinatorDelegateSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegate(delegateSpy)
			.build()

		let url = try #require(URL(string: "test://delegate"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(delegateSpy.willProcessCalls.contains(url))
		#expect(delegateSpy.didProcessCalls.count == 1)
	}

	@Test
	func `delegate with multiple creates composite delegate`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = CoordinatorDelegateSpy()
		let spy2 = CoordinatorDelegateSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegate(spy1)
			.delegate(spy2)
			.build()

		let url = try #require(URL(string: "test://composite"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		// Delegate callbacks are awaited inside `handle(url:)` via
		// `notifyDelegateWillProcess` / `notifyDelegateDidProcess`, and the
		// composite delegate forwards synchronously. No sleep is required.
		#expect(spy1.willProcessCalls.contains(url))
		#expect(spy2.willProcessCalls.contains(url))
		#expect(spy1.didProcessCalls.count == 1)
		#expect(spy2.didProcessCalls.count == 1)
	}

	@Test
	func `delegates with array adds multiple delegates`() throws {
		let spy1 = CoordinatorDelegateSpy()
		let spy2 = CoordinatorDelegateSpy()

		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegates([spy1, spy2])
			.build()
	}

	// MARK: - Custom Middleware Coordinator Tests

	@Test
	func `middlewareCoordinator uses provided coordinator`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let customCoordinator = DeepLinkMiddlewareCoordinator()
		let middlewareSpy = MiddlewareSpy()

		await customCoordinator.add(middlewareSpy)

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middlewareCoordinator(customCoordinator)
			.build()

		let url = try #require(URL(string: "test://custom"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	// MARK: - Method Chaining Tests

	@Test
	func `builder supports full method chaining`() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()
		let delegateSpy = CoordinatorDelegateSpy()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(spy1, spy2)
			.delegate(delegateSpy)
			.build()

		let url = try #require(URL(string: "test://chaining"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(spy1.requests.contains(url))
		#expect(spy2.requests.contains(url))
		#expect(delegateSpy.willProcessCalls.contains(url))
	}

	// MARK: - Error Handling Tests

	@Test
	func `build handles middleware errors gracefully`() async throws {
		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(ErrorMiddleware())
			.build()

		let url = try #require(URL(string: "test://error"))
		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(result.hasErrors)
	}

	// MARK: - routeExecutionDelay + sleep seam

	@Test
	func `routeExecutionDelay and sleep propagate from builder to coordinator`() async throws {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1, .route2, .route3]
		let recorder = SleepRecorder()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.routeExecutionDelay(.milliseconds(500))
			.sleep { await recorder.record($0) }
			.build()

		let url = try #require(URL(string: "test://delay"))
		_ = await coordinator.handle(url: url)

		let recorded = await recorder.durations
		#expect(recorded == [.milliseconds(500), .milliseconds(500)])
	}

	@Test
	func `builder sleep seam is ignored when routeExecutionDelay defaults to zero`() async throws {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1, .route2]
		let recorder = SleepRecorder()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.sleep { await recorder.record($0) }
			.build()

		let url = try #require(URL(string: "test://no-delay"))
		_ = await coordinator.handle(url: url)

		let recorded = await recorder.durations
		#expect(recorded.isEmpty)
	}
}

// MARK: - Test Doubles

private final class MiddlewareSpy: DeepLinkMiddleware, @unchecked Sendable {
	private(set) var requests: [URL] = []

	func intercept(_ url: URL) async throws -> URL? {
		requests.append(url)
		return url
	}
}

private final class ErrorMiddleware: DeepLinkMiddleware {
	func intercept(_: URL) async throws -> URL? {
		throw DeepLinkError.securityViolation("Test security violation")
	}
}

private actor SleepRecorder {
	private(set) var durations: [Duration] = []

	func record(_ duration: Duration) {
		durations.append(duration)
	}
}
