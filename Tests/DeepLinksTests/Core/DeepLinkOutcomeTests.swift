//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

/// One test per way ``DeepLinkOutcome`` is decided, observed through
/// ``DeepLinkMiddleware/didFinish(_:outcome:)``.
struct DeepLinkOutcomeTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `every route succeeding is succeeded`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()

		_ = await makeCoordinator(middleware: [recorder]).handle(url: url)

		#expect(await outcomes.next() == "succeeded")
	}

	@Test
	func `middleware returning nil is stopped`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()

		_ = await makeCoordinator(middleware: [recorder, StoppingMiddleware()]).handle(url: url)

		#expect(await outcomes.next() == "stopped")
	}

	@Test
	func `a readiness gate holding the link is deferred`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()

		_ = await makeCoordinator(middleware: [recorder, ReadinessMiddleware(queue: DeepLinkReadinessQueue())]).handle(url: url)

		#expect(await outcomes.next() == "deferred")
	}

	@Test
	func `a throwing middleware is failed`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()

		_ = await makeCoordinator(middleware: [recorder, ThrowingMiddleware()]).handle(url: url)

		#expect(await outcomes.next() == "failed")
	}

	@Test
	func `a routing error is failed`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let coordinator = makeCoordinator(middleware: [recorder], parser: ImmediateParser(error: DeepLinkError.routeNotFound(url)))

		_ = await coordinator.handle(url: url)

		#expect(await outcomes.next() == "failed")
	}

	@Test
	func `route guards declining every route is failed, since nothing ran`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let handler = CollectingHandler<TestRoute>().confirming(.all) { _, _ in false }

		_ = await makeCoordinator(middleware: [recorder], routes: [.route1, .route2], handler: handler).handle(url: url)

		#expect(await outcomes.next() == "failed")
	}

	@Test
	func `a declined route next to one that ran is handler failed`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let handler = CollectingHandler<TestRoute>().confirming(.all) { route, _ in route == .route1 }

		_ = await makeCoordinator(middleware: [recorder], routes: [.route1, .route2], handler: handler).handle(url: url)

		#expect(await outcomes.next() == "handlerFailed")
	}

	@Test
	func `a handler throwing is handler failed`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()

		_ = await makeCoordinator(middleware: [recorder], handler: ThrowingHandler()).handle(url: url)

		#expect(await outcomes.next() == "handlerFailed")
	}

	@Test(.timeLimit(.minutes(1)))
	func `a queued link the queue evicts is stopped`() async throws {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let queue = DeepLinkReadinessQueue(maxQueueSize: 1)
		let coordinator = makeCoordinator(middleware: [recorder, ReadinessMiddleware(queue: queue)])
		_ = await coordinator.handle(url: url)
		#expect(await outcomes.next() == "deferred")

		_ = try await coordinator.handle(url: #require(URL(string: "myapp://other")))
		let settled = await [outcomes.next(), outcomes.next()]

		#expect(settled.compactMap(\.self).sorted() == ["deferred", "stopped"])
	}

	@Test(.timeLimit(.minutes(1)))
	func `a queued link the queue resets is stopped`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let queue = DeepLinkReadinessQueue()
		_ = await makeCoordinator(middleware: [recorder, ReadinessMiddleware(queue: queue)]).handle(url: url)
		#expect(await outcomes.next() == "deferred")

		queue.reset()

		#expect(await outcomes.next() == "stopped")
	}

	@Test
	func `a drained link settles with the drained pass's outcome`() async {
		let recorder = OutcomeRecorder()
		var outcomes = recorder.outcomes.makeAsyncIterator()
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(middleware: [recorder, ReadinessMiddleware(queue: queue), ThrowingMiddleware()])
		_ = await coordinator.handle(url: url)
		#expect(await outcomes.next() == "deferred")

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(await outcomes.next() == "failed")
	}

	private func makeCoordinator(
		middleware: [any DeepLinkMiddleware],
		parser: (any DeepLinkParser<TestRoute>)? = nil,
		routes: [TestRoute] = [.route1],
		handler: any DeepLinkHandler<TestRoute> = CollectingHandler<TestRoute>(),
	) -> DeepLinkCoordinator<TestRoute> {
		DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [parser ?? ImmediateParser(routes: routes)]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
		)
	}
}

// MARK: - Test Doubles

/// Publishes each outcome it is told about, so a test awaits settlement
/// that happens on another task instead of polling for it.
private final class OutcomeRecorder: DeepLinkMiddleware {
	private let stream = AsyncStream<String>.makeStream()

	var outcomes: AsyncStream<String> {
		stream.stream
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		request
	}

	func didFinish(_: DeepLinkRequest, outcome: DeepLinkOutcome) async {
		let name = switch outcome {
		case .succeeded: "succeeded"
		case .stopped: "stopped"
		case .deferred: "deferred"
		case .failed: "failed"
		case .handlerFailed: "handlerFailed"
		}
		stream.continuation.yield(name)
	}
}

private struct ThrowingMiddleware: DeepLinkMiddleware {
	func intercept(_: DeepLinkRequest) async throws -> DeepLinkRequest? {
		throw DeepLinkError.securityViolation("outcome")
	}
}

private struct ThrowingHandler: DeepLinkHandler {
	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		throw DeepLinkError.handlerError(message: "outcome", underlyingError: nil)
	}
}
