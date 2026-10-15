//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct DeepLinkCoordinatorCancellationTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `a cancelled caller still runs every route and settles middleware`() async {
		let handler = GatedHandler()
		let finishes = FinishLog()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1, TestRoute.route2])]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [finishes]),
		)
		let caller = Task { await coordinator.handle(url: url) }
		await handler.firstRouteStarted()

		caller.cancel()
		handler.open()
		let result = await caller.value

		#expect(result.successfulRoutes == 2)
		#expect(handler.handled == [.route1, .route2])
		#expect(finishes.outcomes == ["succeeded"])
	}

	@Test
	func `a caller cancelled before handling still runs the link`() async {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler,
		)
		let caller = Task {
			withUnsafeCurrentTask { $0?.cancel() }
			return await coordinator.handle(url: url)
		}

		let result = await caller.value

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes == [.route1])
	}
}

// MARK: - Helpers

private final class GatedHandler: DeepLinkHandler {
	private struct State {
		var handled: [TestRoute] = []
		var isOpen = false
		var startWaiter: CheckedContinuation<Void, Never>?
		var openWaiter: CheckedContinuation<Void, Never>?
	}

	private let state = OSAllocatedUnfairLock(initialState: State())

	var handled: [TestRoute] {
		state.withLock { $0.handled }
	}

	func firstRouteStarted() async {
		await withCheckedContinuation { continuation in
			let isStarted = state.withLock { state in
				guard state.handled.isEmpty else { return true }
				state.startWaiter = continuation
				return false
			}
			if isStarted {
				continuation.resume()
			}
		}
	}

	func open() {
		let waiter = state.withLock { state in
			state.isOpen = true
			defer { state.openWaiter = nil }
			return state.openWaiter
		}
		waiter?.resume()
	}

	func handle(_ route: TestRoute, context _: DeepLinkContext) async throws {
		await withCheckedContinuation { continuation in
			let (startWaiter, isOpen) = state.withLock { state in
				state.handled.append(route)
				defer { state.startWaiter = nil }
				if !state.isOpen {
					state.openWaiter = continuation
				}
				return (state.startWaiter, state.isOpen)
			}
			startWaiter?.resume()
			if isOpen {
				continuation.resume()
			}
		}
	}
}

private final class FinishLog: DeepLinkMiddleware {
	private let recorded = OSAllocatedUnfairLock<[String]>(initialState: [])

	var outcomes: [String] {
		recorded.withLock { $0 }
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
		recorded.withLock { $0.append(name) }
	}
}
