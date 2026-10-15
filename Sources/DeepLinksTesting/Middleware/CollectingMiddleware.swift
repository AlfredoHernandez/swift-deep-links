//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// A middleware that passes all URLs through and collects them for inspection.
///
/// `CollectingMiddleware` records every URL that passes through the middleware pipeline
/// without modifying or blocking any of them. Thread-safe through lock protection.
///
/// ## Overview
///
/// Create a `CollectingMiddleware`, add it to your coordinator, and verify which URLs were processed:
///
///     let middleware = CollectingMiddleware()
///     await coordinator.add(middleware)
///     await coordinator.handle(url: someURL)
///
///     #expect(middleware.interceptedURLs == [someURL])
///
/// ## Verifying URL Pipeline
///
/// Track all URLs that pass through the middleware stack:
///
///     let middleware = CollectingMiddleware()
///     let handler = CollectingHandler<AppRoute>()
///     let coordinator = DeepLinkCoordinator(
///         routing: routing,
///         handler: handler,
///         middlewareCoordinator: middlewareCoordinator
///     )
///     await coordinator.add(middleware)
///
///     let url1 = URL(string: "app://home")!
///     let url2 = URL(string: "app://profile")!
///     await coordinator.handle(url: url1)
///     await coordinator.handle(url: url2)
///
///     #expect(middleware.interceptedURLs == [url1, url2])
///
/// - Note: This middleware always returns the URL unchanged, never blocking or redirecting.
/// - Complexity: O(1) for recording each URL.
/// - SeeAlso: `PassthroughMiddleware`, `CollectingHandler`
public final class CollectingMiddleware: DeepLinkMiddleware {
	private let state = OSAllocatedUnfairLock(initialState: [DeepLinkRequest]())

	/// Initializes a new collecting middleware with no recorded URLs.
	public init() {}

	/// All URLs that have been intercepted, in order.
	///
	/// Access this property to assert which URLs were processed by the middleware pipeline.
	/// The URLs are stored in the order they were received.
	public var interceptedURLs: [URL] {
		state.withLock { $0.map(\.url) }
	}

	/// All requests that have been intercepted, in order, with their ``DeepLinkContext``.
	public var interceptedRequests: [DeepLinkRequest] {
		state.withLock { $0 }
	}

	/// Records `request`, with its context, and passes it through unchanged.
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		state.withLock { $0.append(request) }
		return request
	}
}
