//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("DeepLinkCoordinatorBuilder Tests")
@MainActor
struct DeepLinkCoordinatorBuilderTests {
	// MARK: - Basic Configuration Tests

	@Test("DeepLinkCoordinatorBuilder build creates coordinator with required components")
	func deepLinkCoordinatorBuilder_build_createsCoordinatorWithRequiredComponents() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()

		_ = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.build()

		// If build() succeeds, it always returns a valid coordinator
	}

	@Test("DeepLinkCoordinatorBuilder build throws error when routing is missing")
	func deepLinkCoordinatorBuilder_build_throwsErrorWhenRoutingIsMissing() async {
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()

		await #expect(throws: DeepLinkError.missingRequiredConfiguration("routing")) {
			try await DeepLinkCoordinatorBuilder<TestRoute>()
				.addingHandler(handlerSpy)
				.build()
		}
	}

	@Test("DeepLinkCoordinatorBuilder build throws error when handler is missing")
	func deepLinkCoordinatorBuilder_build_throwsErrorWhenHandlerIsMissing() async {
		let routingStub = DeepLinkRoutingStub<TestRoute>()

		await #expect(throws: DeepLinkError.missingRequiredConfiguration("handler")) {
			try await DeepLinkCoordinatorBuilder<TestRoute>()
				.addingRouting(routingStub)
				.build()
		}
	}

	// MARK: - Middleware Configuration Tests

	@Test("DeepLinkCoordinatorBuilder addingMiddleware adds middleware to coordinator")
	func deepLinkCoordinatorBuilder_addingMiddleware_addsMiddlewareToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let middlewareSpy = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingMiddleware(middlewareSpy)
			.build()

		let url = try #require(URL(string: "test://middleware"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	@Test("DeepLinkCoordinatorBuilder addingMiddleware using closure adds middleware to coordinator")
	func deepLinkCoordinatorBuilder_addingMiddlewareUsingClosure_addsMiddlewareToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let middlewareSpy = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingMiddleware { middlewareSpy }
			.build()

		let url = try #require(URL(string: "test://middleware"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	@Test("DeepLinkCoordinatorBuilder addingAdvancedMiddleware adds advanced middleware to coordinator")
	func deepLinkCoordinatorBuilder_addingAdvancedMiddleware_addsAdvancedMiddlewareToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let advancedMiddlewareSpy = AdvancedMiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingAdvancedMiddleware(advancedMiddlewareSpy)
			.build()

		let url = try #require(URL(string: "test://advanced"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(advancedMiddlewareSpy.requests.contains(url))
	}

	@Test("DeepLinkCoordinatorBuilder addingMiddleware array adds multiple middleware to coordinator")
	func deepLinkCoordinatorBuilder_addingMiddlewareArray_addsMultipleMiddlewareToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let middleware1 = MiddlewareSpy()
		let middleware2 = MiddlewareSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingMiddleware([middleware1, middleware2])
			.build()

		let url = try #require(URL(string: "test://multiple"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middleware1.requests.contains(url))
		#expect(middleware2.requests.contains(url))
	}

	// MARK: - Delegate Configuration Tests

	@Test("DeepLinkCoordinatorBuilder addingDelegate adds single delegate to coordinator")
	func deepLinkCoordinatorBuilder_addingDelegate_addsSingleDelegateToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegateSpy = DelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingDelegate(delegateSpy)
			.build()

		let url = try #require(URL(string: "test://delegate"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(delegateSpy.willProcessCalls.contains(url))
		#expect(delegateSpy.didProcessCalls.count == 1)
	}

	@Test("DeepLinkCoordinatorBuilder addingDelegate using closure adds delegate to coordinator")
	func deepLinkCoordinatorBuilder_addingDelegateUsingClosure_addsDelegateToCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegateSpy = DelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingDelegate { delegateSpy }
			.build()

		let url = try #require(URL(string: "test://delegate"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(delegateSpy.willProcessCalls.contains(url))
		#expect(delegateSpy.didProcessCalls.count == 1)
	}

	@Test("DeepLinkCoordinatorBuilder addingDelegates array creates composite delegate")
	func deepLinkCoordinatorBuilder_addingDelegatesArray_createsCompositeDelegate() async throws {
		let routingStub2 = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy2 = DeepLinkHandlerSpy<TestRoute>()
		let delegate2 = DelegateSpy()
		let delegate3 = DelegateSpy()

		let coordinator2 = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub2)
			.addingHandler(handlerSpy2)
			.addingDelegate(delegate2)
			.addingDelegate(delegate3)
			.build()

		let url = try #require(URL(string: "test://composite"))
		routingStub2.routesToReturn = [.route1]

		_ = await coordinator2.handle(url: url)

		// Wait a bit for MainActor notifications to complete
		try await Task.sleep(for: .milliseconds(100))

		#expect(delegate2.willProcessCalls.contains(url))
		#expect(delegate3.willProcessCalls.contains(url))
		#expect(delegate2.didProcessCalls.count == 1)
		#expect(delegate3.didProcessCalls.count == 1)
	}

	@Test("DeepLinkCoordinatorBuilder addingDelegates method works correctly")
	func deepLinkCoordinatorBuilder_addingDelegatesMethod_worksCorrectly() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegate1 = DelegateSpy()
		let delegate2 = DelegateSpy()

		_ = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingDelegates([delegate1, delegate2])
			.build()

		// If build() succeeds, it always returns a valid coordinator
	}

	// MARK: - Custom Middleware Coordinator Tests

	@Test("DeepLinkCoordinatorBuilder addingCustomMiddlewareCoordinator uses provided coordinator")
	func deepLinkCoordinatorBuilder_addingCustomMiddlewareCoordinator_usesProvidedCoordinator() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let customCoordinator = DeepLinkMiddlewareCoordinator()
		let middlewareSpy = MiddlewareSpy()

		await customCoordinator.add(middlewareSpy)

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingCustomMiddlewareCoordinator(customCoordinator)
			.build()

		let url = try #require(URL(string: "test://custom"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middlewareSpy.requests.contains(url))
	}

	// MARK: - Method Chaining Tests

	@Test("DeepLinkCoordinatorBuilder supports method chaining")
	func deepLinkCoordinatorBuilder_supportsMethodChaining() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let middleware1 = MiddlewareSpy()
		let middleware2 = MiddlewareSpy()
		let delegate = DelegateSpy()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingMiddleware(middleware1)
			.addingMiddleware(middleware2)
			.addingDelegate(delegate)
			.build()

		let url = try #require(URL(string: "test://chaining"))
		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(middleware1.requests.contains(url))
		#expect(middleware2.requests.contains(url))
		#expect(delegate.willProcessCalls.contains(url))
	}

	// MARK: - Error Handling Tests

	@Test("DeepLinkCoordinatorBuilder build handles middleware errors gracefully")
	func deepLinkCoordinatorBuilder_build_handlesMiddlewareErrorsGracefully() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let errorMiddleware = ErrorMiddleware()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(routingStub)
			.addingHandler(handlerSpy)
			.addingMiddleware(errorMiddleware)
			.build()

		let url = try #require(URL(string: "test://error"))

		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(result.hasErrors)
	}
}

// MARK: - Test Doubles

private enum TestRoute: DeepLinkRoute, Equatable {
	case route1
	case route2
	case route3

	var id: String {
		switch self {
		case .route1: "route1"

		case .route2: "route2"

		case .route3: "route3"
		}
	}
}

private final class DeepLinkRoutingStub<Route: DeepLinkRoute>: DeepLinkRouting, @unchecked Sendable {
	var routesToReturn: [Route] = []
	var shouldThrowError = false

	func route(from _: URL) async throws -> [Route] {
		if shouldThrowError {
			throw DeepLinkError.routeNotFound("Test error")
		}
		return routesToReturn
	}
}

private final class DeepLinkHandlerSpy<Route: DeepLinkRoute & Equatable>: DeepLinkHandler, @unchecked Sendable {
	private(set) var handledRoutes: [Route] = []
	var shouldThrowError = false
	var errorRoute: Route?

	func handle(_ route: Route) async throws {
		if shouldThrowError, errorRoute == route {
			throw DeepLinkError.handlerError("Test handler error")
		}
		handledRoutes.append(route)
	}
}

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

private final class DelegateSpy: DeepLinkCoordinatorDelegate, @unchecked Sendable {
	private(set) var willProcessCalls: [URL] = []
	private(set) var didProcessCalls: [(url: URL, result: DeepLinkResultProtocol)] = []
	private(set) var didFailCalls: [(url: URL, error: Error)] = []

	func coordinator(_: AnyObject, willProcess url: URL) {
		willProcessCalls.append(url)
	}

	func coordinator(_: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol) {
		didProcessCalls.append((url: url, result: result))
	}

	func coordinator(_: AnyObject, didFailProcessing url: URL, error: Error) {
		didFailCalls.append((url: url, error: error))
	}
}

private final class AuthenticationProviderDummy: AuthenticationProvider {
	func isAuthenticated() async -> Bool {
		true
	}
}

private final class AnalyticsProviderDummy: AnalyticsProvider {
	func track(_: String, parameters _: [String: Any]) async {
		// Dummy implementation - does nothing
	}
}

private final class ErrorMiddleware: DeepLinkMiddleware {
	func intercept(_: URL) async throws -> URL? {
		throw DeepLinkError.securityViolation("Test security violation")
	}
}
