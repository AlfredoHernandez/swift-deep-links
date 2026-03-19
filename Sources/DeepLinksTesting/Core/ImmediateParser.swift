//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A parser that immediately returns preconfigured routes without inspecting the URL.
///
/// `ImmediateParser` bypasses URL pattern matching and returns predetermined routes on every call.
/// This is useful for testing routing or coordinator behavior with known routes,
/// or for simulating parsing failures.
///
/// ## Overview
///
/// Create an `ImmediateParser` with routes to return for any input:
///
///     let parser = ImmediateParser<AppRoute>(routes: [.settings(section: "account")])
///     let routing = DefaultDeepLinkRouting(parsers: [parser])
///
/// ## Testing Multiple Parsers
///
/// Use multiple parsers to test fallback behavior:
///
///     let parser1 = ImmediateParser<AppRoute>(routes: [.home])
///     let parser2 = ImmediateParser<AppRoute>(error: ParsingError.unsupported)
///     let routing = DefaultDeepLinkRouting(parsers: [parser1, parser2])
///
/// - Note: The input URL is ignored; the parser always returns the same routes.
/// - SeeAlso: `ImmediateRouting`, `DeepLinkParser`
public struct ImmediateParser<Route: DeepLinkRoute>: DeepLinkParser, Sendable {
	private let routes: [Route]
	private let error: (any Error)?

	/// Creates a parser that always returns the given routes.
	///
	/// Every call to `parse(from:)` will return these routes regardless of the input URL.
	///
	/// - Parameter routes: The routes to return for any URL
	public init(routes: [Route]) {
		self.routes = routes
		error = nil
	}

	/// Creates a parser that always throws the given error.
	///
	/// Every call to `parse(from:)` will throw this error regardless of the input URL.
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
