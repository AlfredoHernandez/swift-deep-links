//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct ReadinessDrainMiddlewareResumptionTests {
	private let protectedURL = URL(string: "myapp://account")!
	private let publicURL = URL(string: "myapp://home")!

	@Test
	func `drain blocks a queued link when authentication placed after readiness rejects it`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [
			ReadinessMiddleware(queue: queue),
			AuthenticationMiddleware(
				authProvider: FixedAuthenticationProvider(isAuthenticated: false),
				protectedHosts: ["account"],
			),
		])

		_ = await coordinator.handle(url: protectedURL)
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes.isEmpty)
		#expect(results.count == 1)
		#expect(results.first?.firstDeepLinkError == .unauthorizedAccess(protectedURL))
	}

	@Test
	func `drain evaluates authentication at drain time rather than at enqueue time`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let session = SwitchableAuthenticationProvider(isAuthenticated: true)
		let coordinator = makeCoordinator(handler: handler, middleware: [
			ReadinessMiddleware(queue: queue),
			AuthenticationMiddleware(authProvider: session, protectedHosts: ["account"]),
		])

		_ = await coordinator.handle(url: protectedURL)
		session.signOut()
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes.isEmpty)
		#expect(results.first?.firstDeepLinkError == .unauthorizedAccess(protectedURL))
	}

	@Test
	func `drain blocks a queued link when security placed after readiness rejects it`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [
			ReadinessMiddleware(queue: queue),
			SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["home"]),
		])

		_ = await coordinator.handle(url: protectedURL)
		_ = await coordinator.handle(url: publicURL)
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes == [.route1])
		#expect(results.map(\.wasSuccessful) == [false, true])
	}

	@Test
	func `drain runs middleware after readiness once and never re-runs middleware before it`() async {
		let queue = DeepLinkReadinessQueue()
		let beforeReadiness = CollectingMiddleware()
		let afterReadiness = CollectingMiddleware()
		let coordinator = makeCoordinator(handler: CollectingHandler<TestRoute>(), middleware: [
			beforeReadiness,
			ReadinessMiddleware(queue: queue),
			afterReadiness,
		])

		_ = await coordinator.handle(url: publicURL)
		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(beforeReadiness.interceptedURLs == [publicURL])
		#expect(afterReadiness.interceptedURLs == [publicURL])
	}

	@Test
	func `drain reports the URL produced by middleware after readiness as the processed URL`() async throws {
		let queue = DeepLinkReadinessQueue()
		let rewrittenURL = try #require(URL(string: "myapp://rewritten"))
		let coordinator = makeCoordinator(handler: CollectingHandler<TestRoute>(), middleware: [
			ReadinessMiddleware(queue: queue),
			RewritingMiddleware(replacement: rewrittenURL),
		])

		_ = await coordinator.handle(url: publicURL)
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(results.first?.originalURL == publicURL)
		#expect(results.first?.processedURL == rewrittenURL)
	}

	@Test
	func `drain reports a stopped result when middleware after readiness returns nil`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [
			ReadinessMiddleware(queue: queue),
			StoppingMiddleware(),
		])

		_ = await coordinator.handle(url: publicURL)
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes.isEmpty)
		#expect(results.first?.wasStoppedByMiddleware == true)
	}

	@Test
	func `drain runs the whole chain when the drained queue is not registered as readiness middleware`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [
			SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["home"]),
		])

		_ = queue.enqueue(protectedURL)
		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes.isEmpty)
		#expect(results.first?.wasSuccessful == false)
	}

	private func makeCoordinator(
		handler: CollectingHandler<TestRoute>,
		middleware: [any DeepLinkMiddleware],
	) -> DeepLinkCoordinator<TestRoute> {
		DeepLinkCoordinator(
			routing: ImmediateRouting<TestRoute>(routes: [.route1]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
		)
	}
}

// MARK: - Test Doubles

private final class SwitchableAuthenticationProvider: AuthenticationProvider {
	private let authenticated: OSAllocatedUnfairLock<Bool>

	init(isAuthenticated: Bool) {
		authenticated = OSAllocatedUnfairLock(initialState: isAuthenticated)
	}

	func signOut() {
		authenticated.withLock { $0 = false }
	}

	func isAuthenticated() -> Bool {
		authenticated.withLock { $0 }
	}
}

private struct RewritingMiddleware: DeepLinkMiddleware {
	let replacement: URL

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		request.replacingURL(replacement)
	}
}
