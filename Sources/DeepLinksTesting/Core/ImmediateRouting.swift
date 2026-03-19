//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A routing implementation that immediately returns preconfigured routes without performing any URL parsing.
///
/// `ImmediateRouting` bypasses the normal URL parsing flow and returns predetermined routes on every call.
/// This is useful for testing handlers or coordinators in isolation without needing real parsers,
/// or for simulating error conditions.
///
/// ## Overview
///
/// Create an `ImmediateRouting` with either a list of routes to return or an error to throw:
///
///     let routing = ImmediateRouting<AppRoute>(routes: [.profile(userID: "42")])
///     let coordinator = DeepLinkCoordinator(routing: routing, handler: myHandler)
///     await coordinator.handle(url: anyURL)
///
/// ## Testing Error Conditions
///
/// Simulate routing failures by providing an error:
///
///     let routing = ImmediateRouting<AppRoute>(error: NetworkError.offline)
///     // Any URL passed will throw NetworkError.offline
///
/// - Note: This implementation ignores the input URL and always returns the same routes.
/// - SeeAlso: `ImmediateParser`, `DeepLinkRouting`
public struct ImmediateRouting<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
	private let routes: [Route]
	private let error: (any Error)?

	/// Creates a routing that always returns the given routes.
	///
	/// Every call to `route(from:)` will return these routes regardless of the input URL.
	///
	/// - Parameter routes: The routes to return for any URL
	public init(routes: [Route]) {
		self.routes = routes
		error = nil
	}

	/// Creates a routing that always throws the given error.
	///
	/// Every call to `route(from:)` will throw this error regardless of the input URL.
	///
	/// - Parameter error: The error to throw for any URL
	public init(error: some Error) {
		routes = []
		self.error = error
	}

	public func route(from _: URL) async throws -> [Route] {
		if let error { throw error }
		return routes
	}
}
