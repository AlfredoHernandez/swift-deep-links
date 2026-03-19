//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// A middleware that passes all URLs through and collects them for inspection.
///
/// Use this to verify which URLs were intercepted by the middleware pipeline.
///
/// ```swift
/// let middleware = CollectingMiddleware()
/// await coordinator.add(middleware)
/// await coordinator.handle(url: someURL)
///
/// #expect(middleware.interceptedURLs == [someURL])
/// ```
public final class CollectingMiddleware: DeepLinkMiddleware, @unchecked Sendable {
	private let state = OSAllocatedUnfairLock(initialState: [URL]())

	public init() {}

	/// All URLs that have been intercepted, in order.
	public var interceptedURLs: [URL] {
		state.withLock { $0 }
	}

	public func intercept(_ url: URL) async throws -> URL? {
		state.withLock { $0.append(url) }
		return url
	}
}
