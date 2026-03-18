//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A protocol that defines how to route URLs to appropriate deep link routes.
///
/// The `DeepLinkRouting` protocol is responsible for the high-level routing logic
/// that determines which routes should be generated from a given URL. It acts as
/// the orchestrator between URL parsing and route handling.
///
/// ## Implementation
///
/// The library provides `DefaultDeepLinkRouting` as a standard implementation
/// that tries multiple parsers until one succeeds. You can also implement this
/// protocol directly for custom routing logic:
///
/// ```swift
/// final class CustomDeepLinkRouting: DeepLinkRouting {
///     typealias Route = AppRoute
///
///     func route(from url: URL) async throws -> [AppRoute] {
///         // Custom routing logic
///         let routes = try someCustomParser.parse(from: url)
///         return routes
///     }
/// }
/// ```
///
/// ## Default Implementation
///
/// Most applications should use `DefaultDeepLinkRouting` which:
/// - Tries multiple parsers in sequence
/// - Returns the first successful result
/// - Throws `routeNotFound` if no parser can handle the URL
/// - Logs errors for debugging
///
/// ## See Also
///
/// - ``RoutingOf``
///
/// - AssociatedType Route: The type of route this routing system produces
public protocol DeepLinkRouting<Route>: Sendable {
	/// The type of route this routing system produces.
	associatedtype Route: DeepLinkRoute

	/// Routes a URL to one or more deep link routes.
	///
	/// This method should analyze the URL and determine which routes should be
	/// generated. It may use multiple parsers or custom logic to determine
	/// the appropriate routes.
	///
	/// - Parameter url: The URL to route
	/// - Returns: An array of routes that correspond to the URL
	/// - Throws: `DeepLinkError` or other routing-related errors
	func route(from url: URL) async throws -> [Route]
}
