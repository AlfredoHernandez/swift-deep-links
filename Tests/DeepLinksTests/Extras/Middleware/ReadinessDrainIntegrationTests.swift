//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct ReadinessDrainIntegrationTests {
	private let firstURL = URL(string: "myapp://first")!
	private let secondURL = URL(string: "myapp://second")!

	@Test
	func `drain processes every queued URL in order`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		_ = await coordinator.handle(url: firstURL)
		_ = await coordinator.handle(url: secondURL)

		#expect(handler.handledRoutes.isEmpty)
		#expect(queue.pendingCount == 2)

		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes == [.route1, .route1])
		#expect(results.map(\.originalURL) == [firstURL, secondURL])
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `drain resumes the chain after readiness so later middleware sees each drained URL once`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let collector = CollectingMiddleware()
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				ReadinessMiddleware(queue: queue),
				collector,
			]),
		)

		_ = await coordinator.handle(url: firstURL)
		_ = await coordinator.handle(url: secondURL)

		#expect(collector.interceptedURLs.isEmpty)

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes == [.route1, .route1])
		#expect(collector.interceptedURLs == [firstURL, secondURL])
	}

	@Test
	func `drain on an empty queue returns no results and does not invoke the handler`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(results.isEmpty)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `drain continues past a routing failure and records the error per URL`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let routing = FailingRouting(failOn: firstURL, fallbackRoute: .route1)
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		_ = await coordinator.handle(url: firstURL)
		_ = await coordinator.handle(url: secondURL)

		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(results.count == 2)
		#expect(results[0].wasSuccessful == false)
		#expect(results[0].firstDeepLinkError == .unsupportedHost("first"))
		#expect(results[1].wasSuccessful == true)
		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `drain continues past a handler failure and surfaces the error in the result`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = FailingHandler(failOn: .route1, fallbackError: DeepLinkError.handlerError(
			message: "handler exploded",
			underlyingError: nil,
		))
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		_ = await coordinator.handle(url: firstURL)
		_ = await coordinator.handle(url: secondURL)

		let results = await coordinator.markReadyAndDrain(queue: queue)

		#expect(results.count == 2)
		#expect(results.allSatisfy { $0.failedRoutes == 1 })
		#expect(results[0].firstDeepLinkError == .handlerError(message: "handler exploded", underlyingError: nil))
		#expect(results[1].firstDeepLinkError == .handlerError(message: "handler exploded", underlyingError: nil))
	}

	@Test
	func `a second drain after markReadyAndDrain is idempotent and returns no results`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		_ = await coordinator.handle(url: firstURL)

		_ = await coordinator.markReadyAndDrain(queue: queue)
		let secondDrain = await coordinator.markReadyAndDrain(queue: queue)

		#expect(secondDrain.isEmpty)
		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	@MainActor
	func `drain notifies the delegate for every drained URL`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let delegate = CollectingDelegate<TestRoute>()
		let routing = ImmediateRouting<TestRoute>(routes: [.route1])
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
			delegate: delegate,
		)

		_ = await coordinator.handle(url: firstURL)
		_ = await coordinator.handle(url: secondURL)

		let willProcessBefore = delegate.willProcessURLs.count
		let didProcessBefore = delegate.processedEvents.count

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(delegate.willProcessURLs.count == willProcessBefore + 2)
		#expect(delegate.processedEvents.count == didProcessBefore + 2)
		#expect(delegate.willProcessURLs.suffix(2) == [firstURL, secondURL])
		#expect(delegate.processedEvents.suffix(2).map(\.url) == [firstURL, secondURL])
	}
}

// MARK: - Test Doubles

/// Routes to `fallbackRoute` for every URL except `failOn`, which throws.
/// Used to exercise the drain path's per-URL error-isolation contract.
private struct FailingRouting: DeepLinkRouting {
	let failOn: URL
	let fallbackRoute: TestRoute

	func route(from url: URL) async throws -> [TestRoute] {
		if url == failOn {
			throw DeepLinkError.unsupportedHost(url.host ?? "")
		}
		return [fallbackRoute]
	}
}

/// Throws `fallbackError` for every invocation of a specific route; used to
/// pin drain behaviour when the handler fails rather than the router.
private struct FailingHandler: DeepLinkHandler {
	let failOn: TestRoute
	let fallbackError: DeepLinkError

	func handle(_ route: TestRoute) async throws {
		if route == failOn {
			throw fallbackError
		}
	}
}
