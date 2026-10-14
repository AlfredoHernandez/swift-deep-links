//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct MiddlewareDidFinishTests {
	@Test
	func `every middleware that ran is told the link succeeded`() async {
		let first = FinishRecorder()
		let second = FinishRecorder()
		let coordinator = makeCoordinator(middleware: [first, second])

		_ = await coordinator.handle(url: url("myapp://a"), context: DeepLinkContext(source: .customScheme))

		#expect(first.finishes == [.init(url: url("myapp://a"), outcome: .succeeded)])
		#expect(second.finishes == [.init(url: url("myapp://a"), outcome: .succeeded)])
	}

	@Test
	func `each middleware receives the request it intercepted`() async {
		let rewriter = RewritingMiddleware(to: url("myapp://b"))
		let recorder = FinishRecorder()
		let coordinator = makeCoordinator(middleware: [rewriter, recorder])

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(rewriter.finishes.map(\.url) == [url("myapp://a")])
		#expect(recorder.finishes.map(\.url) == [url("myapp://b")])
	}

	@Test
	func `middleware after a stop does not run and is not told`() async {
		let before = FinishRecorder()
		let after = FinishRecorder()
		let coordinator = makeCoordinator(middleware: [before, DroppingMiddleware(), after])

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(before.finishes.map(\.outcome) == [.stopped])
		#expect(after.finishes.isEmpty)
	}

	@Test
	func `a throwing middleware and those before it are told the link failed`() async {
		let before = FinishRecorder()
		let thrower = FinishRecorder(throwing: DeepLinkError.securityViolation("no"))
		let coordinator = makeCoordinator(middleware: [before, thrower])

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(before.finishes.map(\.outcome) == [.failed])
		#expect(thrower.finishes.map(\.outcome) == [.failed])
	}

	@Test
	func `routing failure is reported as failed`() async {
		let recorder = FinishRecorder()
		let coordinator = makeCoordinator(middleware: [recorder], parser: ImmediateParser(error: DeepLinkError.routeNotFound(url("myapp://a"))))

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(recorder.finishes.map(\.outcome) == [.failed])
	}

	@Test
	func `handler failure is reported as failed`() async {
		let recorder = FinishRecorder()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: FailingHandler(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [recorder]),
		)

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(recorder.finishes.map(\.outcome) == [.failed])
	}

	@Test
	func `a link queued by readiness is reported as deferred`() async {
		let recorder = FinishRecorder()
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(middleware: [recorder, ReadinessMiddleware(queue: queue)])

		_ = await coordinator.handle(url: url("myapp://a"))

		#expect(recorder.finishes.map(\.outcome) == [.deferred])
	}

	@Test
	func `drained links tell only the middleware after readiness`() async {
		let before = FinishRecorder()
		let after = FinishRecorder()
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(middleware: [before, ReadinessMiddleware(queue: queue), after])
		_ = await coordinator.handle(url: url("myapp://a"))

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(before.finishes.map(\.outcome) == [.deferred])
		#expect(after.finishes.map(\.outcome) == [.succeeded])
	}

	@Test
	func `middleware without a hook keeps working`() async {
		let coordinator = makeCoordinator(middleware: [PassthroughMiddleware()])

		let result = await coordinator.handle(url: url("myapp://a"))

		#expect(result.wasSuccessful)
	}
}

// MARK: - Helpers

private func makeCoordinator(
	middleware: [any DeepLinkMiddleware],
	parser: any DeepLinkParser<TestRoute> = ImmediateParser(routes: [TestRoute.route1]),
) -> DeepLinkCoordinator<TestRoute> {
	DeepLinkCoordinator(
		routing: DefaultDeepLinkRouting(parsers: [parser]),
		handler: CollectingHandler<TestRoute>(),
		middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
	)
}

private func url(_ string: String) -> URL {
	URL(string: string)!
}

private struct Finish: Equatable {
	let url: URL
	let outcome: DeepLinkOutcomeKind
}

/// `DeepLinkOutcome` without the error payload, for equality.
private enum DeepLinkOutcomeKind: Equatable {
	case succeeded, stopped, deferred, failed

	init(_ outcome: DeepLinkOutcome) {
		switch outcome {
		case .succeeded: self = .succeeded
		case .stopped: self = .stopped
		case .deferred: self = .deferred
		case .failed: self = .failed
		}
	}
}

private final class FinishRecorder: DeepLinkMiddleware {
	private let recorded = OSAllocatedUnfairLock<[Finish]>(initialState: [])
	private let error: (any Error & Sendable)?

	init(throwing error: (any Error & Sendable)? = nil) {
		self.error = error
	}

	var finishes: [Finish] {
		recorded.withLock { $0 }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		if let error {
			throw error
		}
		return request
	}

	func didFinish(_ request: DeepLinkRequest, outcome: DeepLinkOutcome) async {
		recorded.withLock { $0.append(Finish(url: request.url, outcome: DeepLinkOutcomeKind(outcome))) }
	}
}

private final class RewritingMiddleware: DeepLinkMiddleware {
	private let target: URL
	private let recorded = OSAllocatedUnfairLock<[Finish]>(initialState: [])

	init(to target: URL) {
		self.target = target
	}

	var finishes: [Finish] {
		recorded.withLock { $0 }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		request.replacingURL(target)
	}

	func didFinish(_ request: DeepLinkRequest, outcome: DeepLinkOutcome) async {
		recorded.withLock { $0.append(Finish(url: request.url, outcome: DeepLinkOutcomeKind(outcome))) }
	}
}

private struct DroppingMiddleware: DeepLinkMiddleware {
	func intercept(_: DeepLinkRequest) async throws -> DeepLinkRequest? {
		nil
	}
}

private struct FailingHandler: DeepLinkHandler {
	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		throw DeepLinkError.handlerError(message: "boom", underlyingError: nil)
	}
}
