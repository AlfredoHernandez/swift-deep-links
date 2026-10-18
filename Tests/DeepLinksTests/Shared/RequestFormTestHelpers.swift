//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation

extension DeepLinkMiddleware {
	/// Runs the request form on `url` with an unknown context and returns the resulting URL.
	func intercept(url: URL) async throws -> URL? {
		try await intercept(DeepLinkRequest(url: url))?.url
	}
}

extension DeepLinkMiddlewareCoordinator {
	/// Runs the request form on `url` with an unknown context and returns the resulting URL.
	func process(url: URL) async throws -> URL? {
		try await process(DeepLinkRequest(url: url))?.url
	}

	/// Resumes the request form after `anchor` and returns the resulting URL.
	func process(url: URL, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> URL? {
		try await process(DeepLinkRequest(url: url), startingAfter: anchor)?.url
	}
}

/// The deprecated URL forms, reached through test-only protocols so the
/// dedicated bridge tests can call them without deprecation warnings.
protocol LegacyURLProcessing: Sendable {
	func process(_ url: URL) async throws -> URL?
	func process(_ url: URL, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> URL?
}

extension DeepLinkMiddlewareCoordinator: LegacyURLProcessing {}

/// Calls the deprecated `intercept(_: URL)` form of `middleware`.
func legacyIntercept(_ middleware: some _DeepLinkURLIntercepting, _ url: URL) async throws -> URL? {
	try await middleware.intercept(url)
}
