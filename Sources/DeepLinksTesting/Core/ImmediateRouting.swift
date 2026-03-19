//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A routing implementation that immediately returns preconfigured routes
/// without performing any URL parsing.
///
/// Useful for testing handlers or coordinators in isolation without
/// needing real parsers.
///
/// ```swift
/// let routing = ImmediateRouting<AppRoute>(routes: [.profile(userID: "42")])
/// let coordinator = DeepLinkCoordinator(routing: routing, handler: myHandler)
/// await coordinator.handle(url: anyURL)
/// ```
public struct ImmediateRouting<Route: DeepLinkRoute>: DeepLinkRouting, Sendable {
	private let routes: [Route]
	private let error: (any Error)?

	/// Creates a routing that always returns the given routes.
	///
	/// - Parameter routes: The routes to return for any URL
	public init(routes: [Route]) {
		self.routes = routes
		error = nil
	}

	/// Creates a routing that always throws the given error.
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
