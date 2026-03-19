//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

/// Integration tests demonstrating how to use `DeepLinksTesting` utilities
/// to test the full deep link coordinator pipeline.
@Suite("DeepLink Coordinator Integration", .serialized)
@MainActor
struct DeepLinkCoordinatorIntegrationTests {
	@Test("Handle delivers stack route on product deep link")
	func handle_deliversStackRoute_onProductDeepLink() async throws {
		let (coordinator, handler) = makeSUT(
			routing: DefaultDeepLinkRouting(parsers: [ProductParser(), ProfileParser()]),
		)

		let url = try #require(URL(string: "deeplink://product?productID=PROD-42&category=Books"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes.count == 1)
		#expect(handler.handledRoutes.first?.id == AppRoute.stack(.product(productID: "PROD-42", category: "Books")).id)
	}

	@Test("Handle delivers sheet route on profile deep link")
	func handle_deliversSheetRoute_onProfileDeepLink() async throws {
		let (coordinator, handler) = makeSUT(
			routing: DefaultDeepLinkRouting(parsers: [ProductParser(), ProfileParser()]),
		)

		let url = try #require(URL(string: "deeplink://profile?userID=99&name=Alice"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes.count == 1)
		#expect(handler.handledRoutes.first?.id == AppRoute.sheet(.profile(userID: "99", name: "Alice")).id)
	}

	@Test("Handle delivers configured routes on immediate routing")
	func handle_deliversConfiguredRoutes_onImmediateRouting() async throws {
		let expectedRoute = AppRoute.stack(.settings(section: "privacy"))
		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting(routes: [expectedRoute]),
		)

		let result = try await coordinator.handle(url: #require(URL(string: "deeplink://anything")))

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes.count == 1)
		#expect(handler.handledRoutes.first?.id == expectedRoute.id)
	}

	@Test("Handle records intercepted URLs on collecting middleware")
	func handle_recordsInterceptedURLs_onCollectingMiddleware() async throws {
		let middleware = CollectingMiddleware()
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		await middlewareCoordinator.add(middleware)

		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting<AppRoute>(routes: [.stack(.settings(section: "account"))]),
			middlewareCoordinator: middlewareCoordinator,
		)

		let url = try #require(URL(string: "deeplink://settings?section=account"))
		await coordinator.handle(url: url)

		#expect(middleware.interceptedURLs == [url])
		#expect(handler.handledRoutes.count == 1)
	}

	@Test("Handle blocks request on unauthorized scheme with security middleware")
	func handle_blocksRequest_onUnauthorizedSchemeWithSecurityMiddleware() async throws {
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		await middlewareCoordinator.add(SecurityMiddleware(allowedSchemes: ["deeplink"]))

		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting<AppRoute>(routes: [.stack(.settings(section: "account"))]),
			middlewareCoordinator: middlewareCoordinator,
		)

		let url = try #require(URL(string: "https://evil.com/settings"))
		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test("Handle allows protected routes on authenticated provider")
	func handle_allowsProtectedRoutes_onAuthenticatedProvider() async throws {
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		await middlewareCoordinator.add(AuthenticationMiddleware(
			authProvider: FixedAuthenticationProvider(isAuthenticated: true),
			protectedHosts: ["profile"],
		))

		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting(routes: [.sheet(.profile(userID: "1", name: "Test"))]),
			middlewareCoordinator: middlewareCoordinator,
		)

		let url = try #require(URL(string: "deeplink://profile?userID=1"))
		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes.count == 1)
	}

	@Test("Handle blocks protected routes on unauthenticated provider")
	func handle_blocksProtectedRoutes_onUnauthenticatedProvider() async throws {
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		await middlewareCoordinator.add(AuthenticationMiddleware(
			authProvider: FixedAuthenticationProvider(isAuthenticated: false),
			protectedHosts: ["profile"],
		))

		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting(routes: [.sheet(.profile(userID: "1", name: "Test"))]),
			middlewareCoordinator: middlewareCoordinator,
		)

		let url = try #require(URL(string: "deeplink://profile?userID=1"))
		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test("Handle records lifecycle events on collecting delegate")
	func handle_recordsLifecycleEvents_onCollectingDelegate() async throws {
		let delegate = CollectingDelegate()
		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting(routes: [.stack(.settings(section: "account"))]),
			delegate: delegate,
		)

		let url = try #require(URL(string: "deeplink://settings"))
		await coordinator.handle(url: url)

		#expect(delegate.willProcessURLs == [url])
		#expect(delegate.processedEvents.count == 1)
		#expect(delegate.processedEvents.first?.result.wasSuccessful == true)
		#expect(delegate.failedEvents.isEmpty)
		#expect(handler.handledRoutes.count == 1)
	}

	@Test("Handle blocks excess requests on rate limit with in-memory persistence")
	func handle_blocksExcessRequests_onRateLimitWithInMemoryPersistence() async throws {
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		await middlewareCoordinator.add(RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60,
			persistence: InMemoryRateLimitPersistence(),
		))

		let (coordinator, handler) = makeSUT(
			routing: ImmediateRouting(routes: [.stack(.settings(section: "account"))]),
			middlewareCoordinator: middlewareCoordinator,
		)

		let url = try #require(URL(string: "deeplink://settings"))

		let result1 = await coordinator.handle(url: url)
		let result2 = await coordinator.handle(url: url)
		#expect(result1.wasSuccessful)
		#expect(result2.wasSuccessful)

		let result3 = await coordinator.handle(url: url)
		#expect(!result3.wasSuccessful)
		#expect(handler.handledRoutes.count == 2)
	}

	// MARK: - Helpers

	private func makeSUT(
		routing: some DeepLinkRouting<AppRoute> = ImmediateRouting<AppRoute>(routes: []),
		middlewareCoordinator: DeepLinkMiddlewareCoordinator = DeepLinkMiddlewareCoordinator(),
		delegate: (any DeepLinkCoordinatorDelegate)? = nil,
	) -> (coordinator: DeepLinkCoordinator<AppRoute>, handler: CollectingHandler<AppRoute>) {
		let handler = CollectingHandler<AppRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: middlewareCoordinator,
			routeExecutionDelay: .zero,
			delegate: delegate,
		)
		return (coordinator, handler)
	}
}
