//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import os

// MARK: - Routes

enum TestRoute: DeepLinkRoute {
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

// MARK: - Core Test Doubles

final class DeepLinkRoutingStub<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
	private struct State {
		var routesToReturn: [Route] = []
		var shouldThrowError = false
		var errorToThrow: any Error & Sendable = DeepLinkError.routeNotFound(URL(string: "test://error")!)
	}

	private let state = OSAllocatedUnfairLock<State>(initialState: State())

	var routesToReturn: [Route] {
		get { state.withLock { $0.routesToReturn } }
		set { state.withLock { $0.routesToReturn = newValue } }
	}

	var shouldThrowError: Bool {
		get { state.withLock { $0.shouldThrowError } }
		set { state.withLock { $0.shouldThrowError = newValue } }
	}

	var errorToThrow: any Error & Sendable {
		get { state.withLock { $0.errorToThrow } }
		set { state.withLock { $0.errorToThrow = newValue } }
	}

	func route(from _: URL) async throws -> [Route] {
		let snapshot = state.withLock { $0 }
		if snapshot.shouldThrowError {
			throw snapshot.errorToThrow
		}
		return snapshot.routesToReturn
	}
}

final class DeepLinkHandlerSpy<Route: DeepLinkRoute>: DeepLinkHandler, Sendable {
	private struct State {
		var handledRoutes: [Route] = []
		var shouldThrowError = false
		var errorRoute: Route?
		var errorToThrow: any Error & Sendable = DeepLinkError.handlerError(message: "Test handler error", underlyingError: nil)
	}

	private let state = OSAllocatedUnfairLock<State>(initialState: State())

	var handledRoutes: [Route] {
		state.withLock { $0.handledRoutes }
	}

	var shouldThrowError: Bool {
		get { state.withLock { $0.shouldThrowError } }
		set { state.withLock { $0.shouldThrowError = newValue } }
	}

	var errorRoute: Route? {
		get { state.withLock { $0.errorRoute } }
		set { state.withLock { $0.errorRoute = newValue } }
	}

	var errorToThrow: any Error & Sendable {
		get { state.withLock { $0.errorToThrow } }
		set { state.withLock { $0.errorToThrow = newValue } }
	}

	/// Outcome of a `handle(_:)` call, decided under the single `withLock` so
	/// the read-then-append window no longer straddles two lock acquisitions.
	private enum Outcome {
		case recorded
		case threw(any Error & Sendable)
	}

	func handle(_ route: Route) async throws {
		let outcome: Outcome = state.withLock { state in
			if state.shouldThrowError, state.errorRoute == route {
				return .threw(state.errorToThrow)
			}
			state.handledRoutes.append(route)
			return .recorded
		}
		if case let .threw(error) = outcome {
			throw error
		}
	}
}

@MainActor
final class CoordinatorDelegateSpy: DeepLinkCoordinatorDelegate {
	private(set) var willProcessCalls: [URL] = []
	private(set) var didProcessCalls: [(url: URL, result: DeepLinkResult<TestRoute>)] = []
	private(set) var didFailCalls: [(url: URL, error: Error)] = []

	func coordinator(_: DeepLinkCoordinator<TestRoute>, willProcess url: URL) {
		willProcessCalls.append(url)
	}

	func coordinator(_: DeepLinkCoordinator<TestRoute>, didProcess url: URL, result: DeepLinkResult<TestRoute>) {
		didProcessCalls.append((url: url, result: result))
	}

	func coordinator(_: DeepLinkCoordinator<TestRoute>, didFailProcessing url: URL, error: Error) {
		didFailCalls.append((url: url, error: error))
	}
}

// MARK: - Middleware Test Doubles

/// Middleware that always returns `nil` to stop URL processing before routing.
final class StoppingMiddleware: DeepLinkMiddleware {
	func intercept(_: URL) async throws -> URL? {
		nil
	}
}

/// Records every analytics event it sees. `@unchecked Sendable` is required
/// because `AnalyticsProvider.track(_:parameters:)` forwards `[String: Any]`,
/// whose value type is not itself `Sendable`, which rules out lock-protected
/// Sendable storage. The existing tests consume this spy single-threaded
/// (construct → drive the middleware on one task → read `trackedEvents`), so
/// the unchecked claim holds. Tests that need concurrent writes should prefer
/// `DeepLinksTesting.CollectingAnalyticsProvider`, which stringifies
/// parameters for safe storage.
final class AnalyticsProviderSpy: AnalyticsProvider, @unchecked Sendable {
	struct TrackedEvent {
		let event: String
		let parameters: [String: Any]
	}

	private(set) var trackedEvents: [TrackedEvent] = []

	func track(_ event: String, parameters: [String: Any]) {
		trackedEvents.append(TrackedEvent(event: event, parameters: parameters))
	}
}

final class AuthenticationProviderStub: AuthenticationProvider, Sendable {
	private let authenticated: Bool

	init(isAuthenticated: Bool) {
		authenticated = isAuthenticated
	}

	func isAuthenticated() -> Bool {
		authenticated
	}
}

// MARK: - Parsing Test Doubles

/// A stub parser that either returns a fixed set of routes or throws a
/// configurable error. Lock-protected so tests can safely read
/// `parseCalledWith` from a different actor than the one that invoked
/// `parse(from:)`.
final class DeepLinkParserStub<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
	private struct State {
		var parseCalledWith: URL?
	}

	private let shouldSucceed: Bool
	private let routes: [Route]
	private let state = OSAllocatedUnfairLock<State>(initialState: State())

	init(shouldSucceed: Bool, routes: [Route] = []) {
		self.shouldSucceed = shouldSucceed
		self.routes = routes
	}

	var parseCalledWith: URL? {
		state.withLock { $0.parseCalledWith }
	}

	func parse(from url: URL) async throws -> [Route] {
		state.withLock { $0.parseCalledWith = url }
		if shouldSucceed {
			return routes
		}
		throw TestParserError.parserError
	}
}

/// A parser that always throws the supplied `DeepLinkError`.
struct ThrowingParserStub<Route: DeepLinkRoute>: DeepLinkParser {
	let error: DeepLinkError

	func parse(from _: URL) async throws -> [Route] {
		throw error
	}
}

enum TestParserError: Error {
	case parserError
}

/// Records every message a ``LoggingProvider`` receives.
final class MessageRecorder: Sendable {
	private let state = OSAllocatedUnfairLock<[String]>(initialState: [])

	var all: [String] {
		state.withLock { $0 }
	}

	var joined: String {
		all.joined(separator: "\n")
	}

	var provider: LoggingProvider {
		LoggingProvider { [state] _, message in
			state.withLock { $0.append(message) }
		}
	}
}
