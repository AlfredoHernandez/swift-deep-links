//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A middleware that always passes URLs through unchanged.
///
/// Useful as a no-op placeholder in the middleware pipeline during tests.
///
/// ```swift
/// let coordinator = DeepLinkCoordinator(
///     routing: routing,
///     handler: handler,
///     middlewareCoordinator: middlewareCoordinator
/// )
/// await coordinator.add(PassthroughMiddleware())
/// ```
public struct PassthroughMiddleware: DeepLinkMiddleware, Sendable {
	public init() {}

	public func intercept(_ url: URL) async throws -> URL? {
		url
	}
}
