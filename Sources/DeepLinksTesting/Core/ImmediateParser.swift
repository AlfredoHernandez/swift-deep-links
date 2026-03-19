//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A parser that immediately returns preconfigured routes without
/// inspecting the URL.
///
/// Useful for testing routing or coordinator behavior with known routes.
///
/// ```swift
/// let parser = ImmediateParser<AppRoute>(routes: [.settings(section: "account")])
/// let routing = DefaultDeepLinkRouting(parsers: [parser])
/// ```
public struct ImmediateParser<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
	private let routes: [Route]
	private let error: (any Error)?

	/// Creates a parser that always returns the given routes.
	///
	/// - Parameter routes: The routes to return for any URL
	public init(routes: [Route]) {
		self.routes = routes
		error = nil
	}

	/// Creates a parser that always throws the given error.
	///
	/// - Parameter error: The error to throw for any URL
	public init(error: some Error) {
		routes = []
		self.error = error
	}

	public func parse(from _: URL) async throws -> [Route] {
		if let error { throw error }
		return routes
	}
}
