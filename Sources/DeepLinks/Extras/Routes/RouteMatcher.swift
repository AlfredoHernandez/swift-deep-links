//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Selects parsed routes a handler-level rule applies to, such as the routes
/// a ``SignedRouteGuard`` or ``ConfirmingHandler`` protects.
///
/// Route rules run after parsing, on the route the link actually produced,
/// so they hold however the URL was spelled (encodings, custom-scheme hosts,
/// a second parser accepting another shape). Prefer them to ``DeepLinkMatcher``
/// URL rules for anything sensitive; use URL rules to reject early, before
/// parsing or other middleware runs. When parsers such as
/// ``PathPatternParser`` map several templates or a custom-scheme host to the
/// same route, one route rule covers all of them.
public struct RouteMatcher<Route: DeepLinkRoute>: Sendable {
	private let predicate: @Sendable (Route, DeepLinkContext) -> Bool

	/// Creates a matcher from a predicate over the route and its context.
	public init(_ predicate: @escaping @Sendable (Route, DeepLinkContext) -> Bool) {
		self.predicate = predicate
	}

	/// Whether the rule applies to `route` arriving with `context`.
	public func matches(_ route: Route, context: DeepLinkContext) -> Bool {
		predicate(route, context)
	}
}

// MARK: - Built-in Matchers

public extension RouteMatcher {
	/// Matches every route.
	static var all: RouteMatcher {
		RouteMatcher { _, _ in true }
	}

	/// Matches routes for which `predicate` returns `true`.
	///
	/// ```swift
	/// .routes { if case .payment = $0 { true } else { false } }
	/// ```
	static func routes(where predicate: @escaping @Sendable (Route) -> Bool) -> RouteMatcher {
		RouteMatcher { route, _ in predicate(route) }
	}

	/// A matcher over the route and the context it arrived with.
	static func custom(_ predicate: @escaping @Sendable (Route, DeepLinkContext) -> Bool) -> RouteMatcher {
		RouteMatcher(predicate)
	}
}
