//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct DeepLinkRunScopeTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `a handler calling middleware directly runs it standalone`() async {
		let probe = RunProbe()
		let inner = DeepLinkMiddlewareCoordinator(middleware: [probe])
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: CallingMiddlewareHandler(middleware: inner),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [RunProbe()]),
		)

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(probe.snapshots == [.standalone])
	}

	@Test
	func `middleware inside a coordinator pass sees the pass`() async {
		let probe = RunProbe()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: CollectingHandler<TestRoute>(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [probe]),
		)

		_ = await coordinator.handle(url: url)

		#expect(probe.snapshots == [RunSnapshot(hasID: true, arrival: url, routedURL: nil, hasRouteDecline: false)])
	}

	@Test
	func `a handler sees the routed URL and its route decline`() async {
		let handler = RunObservingHandler()
		let coordinator = DeepLinkCoordinator(routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]), handler: handler)

		_ = await coordinator.handle(url: url)

		#expect(handler.snapshots == [RunSnapshot(hasID: true, arrival: url, routedURL: url, hasRouteDecline: true)])
	}
}

// MARK: - Helpers

private struct RunSnapshot: Equatable {
	static let standalone = RunSnapshot(hasID: false, arrival: nil, routedURL: nil, hasRouteDecline: false)

	let hasID: Bool
	let arrival: URL?
	let routedURL: URL?
	let hasRouteDecline: Bool

	static func current() -> RunSnapshot {
		RunSnapshot(
			hasID: DeepLinkRun.id != nil,
			arrival: DeepLinkRun.arrival?.url,
			routedURL: DeepLinkRun.routedURL,
			hasRouteDecline: DeepLinkRun.routeDecline != nil,
		)
	}
}

private final class RunProbe: DeepLinkMiddleware {
	private let recorded = OSAllocatedUnfairLock<[RunSnapshot]>(initialState: [])

	var snapshots: [RunSnapshot] {
		recorded.withLock { $0 }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		let snapshot = RunSnapshot.current()
		recorded.withLock { $0.append(snapshot) }
		return request
	}
}

private final class RunObservingHandler: DeepLinkHandler {
	private let recorded = OSAllocatedUnfairLock<[RunSnapshot]>(initialState: [])

	var snapshots: [RunSnapshot] {
		recorded.withLock { $0 }
	}

	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		let snapshot = RunSnapshot.current()
		recorded.withLock { $0.append(snapshot) }
	}
}

private struct CallingMiddlewareHandler: DeepLinkHandler {
	let middleware: DeepLinkMiddlewareCoordinator

	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		_ = try await middleware.process(DeepLinkRequest(url: URL(string: "myapp://inner")!))
	}
}
