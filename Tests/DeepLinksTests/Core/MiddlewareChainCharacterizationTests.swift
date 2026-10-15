//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct MiddlewareChainCharacterizationTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `a standalone process queues the link without a deferral`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [CollectingMiddleware(), ReadinessMiddleware(queue: queue)])

		let result = try await sut.process(DeepLinkRequest(url: url))

		#expect(result == nil)
		#expect(queue.pendingRequests.map { $0.deferral == nil } == [true])
	}

	@Test
	func `a coordinator pass queues the link with a deferral`() async {
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(middleware: [CollectingMiddleware(), ReadinessMiddleware(queue: queue)])

		_ = await coordinator.handle(url: url)

		#expect(queue.pendingRequests.map { $0.deferral != nil } == [true])
	}

	@Test
	func `middleware after an open gate never sees the gate's deferral`() async {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()
		let after = CollectingMiddleware()
		let coordinator = makeCoordinator(middleware: [ReadinessMiddleware(queue: queue), after])

		_ = await coordinator.handle(url: url)

		#expect(after.interceptedRequests.map { $0.deferral == nil } == [true])
	}

	@Test
	func `a standalone process rethrows the middleware's error`() async {
		let sut = DeepLinkMiddlewareCoordinator(middleware: [ThrowingMiddleware()])

		await #expect(throws: DeepLinkError.securityViolation("chain")) {
			try await sut.process(DeepLinkRequest(url: url))
		}
	}

	@Test
	func `a drain resumes after the gate of the drained queue only`() async {
		let first = DeepLinkReadinessQueue()
		let second = DeepLinkReadinessQueue()
		_ = second.markReady()
		let between = CollectingMiddleware()
		let after = CollectingMiddleware()
		let coordinator = makeCoordinator(middleware: [
			ReadinessMiddleware(queue: first),
			between,
			ReadinessMiddleware(queue: second),
			after,
		])
		_ = await coordinator.handle(url: url)

		_ = await coordinator.markReadyAndDrain(queue: first)

		#expect(between.interceptedURLs == [url])
		#expect(after.interceptedURLs == [url])
	}
}

// MARK: - Helpers

private func makeCoordinator(middleware: [any DeepLinkMiddleware]) -> DeepLinkCoordinator<TestRoute> {
	DeepLinkCoordinator(
		routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
		handler: CollectingHandler<TestRoute>(),
		middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
	)
}

private struct ThrowingMiddleware: DeepLinkMiddleware {
	func intercept(_: DeepLinkRequest) async throws -> DeepLinkRequest? {
		throw DeepLinkError.securityViolation("chain")
	}
}
