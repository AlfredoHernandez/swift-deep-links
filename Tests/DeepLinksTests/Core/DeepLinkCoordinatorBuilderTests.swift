//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@Suite("DeepLinkCoordinatorBuilder Tests")
@MainActor
struct DeepLinkCoordinatorBuilderTests {
	// MARK: - Basic Configuration Tests

	@Test("build creates coordinator with required components")
	func build_createsCoordinatorWithRequiredComponents() async throws {
		_ = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.build()
	}

	@Test("build throws error when routing is missing")
	func build_throwsErrorWhenRoutingIsMissing() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("routing")) {
			try await DeepLinkCoordinatorBuilder<TestRoute>()
				.handler(DeepLinkHandlerSpy<TestRoute>())
				.build()
		}
	}

	@Test("build throws error when handler is missing")
	func build_throwsErrorWhenHandlerIsMissing() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("handler")) {
			try await DeepLinkCoordinatorBuilder<TestRoute>()
				.routing(DeepLinkRoutingStub<TestRoute>())
				.build()
		}
	}

	// MARK: - Middleware Configuration Tests

	@Test("middleware adds single middleware to coordinator")
	func middleware_addsSingleMiddleware() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let middlewareSpy = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(middlewareSpy)
			.build()

		let url = try #require(URL(string: "test://middleware"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	@Test("advancedMiddleware adds advanced middleware to coordinator")
	func advancedMiddleware_addsAdvancedMiddleware() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let advancedSpy = AdvancedMiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.advancedMiddleware(advancedSpy)
			.build()

		let url = try #require(URL(string: "test://advanced"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(advancedSpy.requests.contains(url))
	}

	@Test("middleware with variadic adds multiple middleware")
	func middleware_withVariadic_addsMultiple() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test("middleware with array adds multiple middleware")
	func middleware_withArray_addsMultiple() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test("delegate adds single delegate to coordinator")
	func delegate_addsSingleDelegate() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let delegateSpy = CoordinatorDelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test("delegate with multiple creates composite delegate")
	func delegate_withMultiple_createsComposite() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = CoordinatorDelegateSpy()
		let spy2 = CoordinatorDelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routingStub)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegate(spy1)
			.delegate(spy2)
			.build()

		let url = try #require(URL(string: "test://composite"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		try await Task.sleep(for: .milliseconds(100))

		#expect(spy1.willProcessCalls.contains(url))
		#expect(spy2.willProcessCalls.contains(url))
		#expect(spy1.didProcessCalls.count == 1)
		#expect(spy2.didProcessCalls.count == 1)
	}

	@Test("delegates with array adds multiple delegates")
	func delegates_withArray_addsMultiple() async throws {
		let spy1 = CoordinatorDelegateSpy()
		let spy2 = CoordinatorDelegateSpy()

		_ = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegates([spy1, spy2])
			.build()
	}

	// MARK: - Custom Middleware Coordinator Tests

	@Test("middlewareCoordinator uses provided coordinator")
	func middlewareCoordinator_usesProvidedCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let customCoordinator = DeepLinkMiddlewareCoordinator()
		let middlewareSpy = MiddlewareSpy()

		await customCoordinator.add(middlewareSpy)

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test("builder supports full method chaining")
	func builder_supportsFullMethodChaining() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let spy1 = MiddlewareSpy()
		let spy2 = MiddlewareSpy()
		let delegateSpy = CoordinatorDelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
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

	@Test("build handles middleware errors gracefully")
	func build_handlesMiddlewareErrorsGracefully() async throws {
		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(ErrorMiddleware())
			.build()

		let url = try #require(URL(string: "test://error"))
		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(result.hasErrors)
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

private final class AdvancedMiddlewareSpy: AdvancedDeepLinkMiddleware, @unchecked Sendable {
	private(set) var requests: [URL] = []

	func intercept(_ url: URL) async -> MiddlewareResult {
		requests.append(url)
		return .continue(url)
	}
}

private final class ErrorMiddleware: DeepLinkMiddleware {
	func intercept(_: URL) async throws -> URL? {
		throw DeepLinkError.securityViolation("Test security violation")
	}
}
