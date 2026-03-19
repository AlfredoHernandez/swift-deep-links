//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A middleware that always passes URLs through unchanged.
///
/// `PassthroughMiddleware` is a no-op middleware that returns the URL unmodified.
/// Use it as a placeholder when testing middleware pipelines or when you need
/// a middleware that performs no filtering or transformation.
///
/// ## Overview
///
/// Use `PassthroughMiddleware` to fill middleware slots without any processing logic:
///
///     let coordinator = DeepLinkCoordinator(
///         routing: routing,
///         handler: handler,
///         middlewareCoordinator: middlewareCoordinator
///     )
///     await coordinator.add(PassthroughMiddleware())
///     await coordinator.handle(url: someURL)
///
/// ## Testing Middleware Pipeline Order
///
/// Combine with `CollectingMiddleware` to test pipeline ordering:
///
///     let collecting = CollectingMiddleware()
///     let passthrough = PassthroughMiddleware()
///     await coordinator.add(collecting)
///     await coordinator.add(passthrough)
///     // Both middleware will process all URLs
///
/// - Note: This middleware always returns the input URL without any transformations.
/// - Complexity: O(1).
/// - SeeAlso: `CollectingMiddleware`, `DeepLinkMiddleware`
public struct PassthroughMiddleware: DeepLinkMiddleware, Sendable {
	/// Initializes a new passthrough middleware.
	public init() {}

	public func intercept(_ url: URL) async throws -> URL? {
		url
	}
}
