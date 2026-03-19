//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation

// MARK: - Routes

enum TestRoute: DeepLinkRoute, Equatable {
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

final class DeepLinkRoutingStub<Route: DeepLinkRoute>: DeepLinkRouting, @unchecked Sendable {
	var routesToReturn: [Route] = []
	var shouldThrowError = false
	var errorToThrow: Error = DeepLinkError.routeNotFound("Test error")

	func route(from _: URL) async throws -> [Route] {
		if shouldThrowError {
			throw errorToThrow
		}
		return routesToReturn
	}
}

final class DeepLinkHandlerSpy<Route: DeepLinkRoute & Equatable>: DeepLinkHandler, @unchecked Sendable {
	private(set) var handledRoutes: [Route] = []
	var shouldThrowError = false
	var errorRoute: Route?
	var errorToThrow: Error = DeepLinkError.handlerError("Test handler error")

	func handle(_ route: Route) async throws {
		if shouldThrowError, errorRoute == route {
			throw errorToThrow
		}
		handledRoutes.append(route)
	}
}

final class CoordinatorDelegateSpy: DeepLinkCoordinatorDelegate, @unchecked Sendable {
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

// MARK: - Middleware Test Doubles

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

final class AuthenticationProviderStub: AuthenticationProvider {
	private let authenticated: Bool

	init(isAuthenticated: Bool) {
		authenticated = isAuthenticated
	}

	func isAuthenticated() -> Bool {
		authenticated
	}
}
