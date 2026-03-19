//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import OSLog

/// Middleware that gates deep link processing on a readiness queue.
///
/// When a deep link arrives before the queue is ready, the URL is
/// stored in the queue and processing stops (`nil` is returned).
/// Once the queue is marked ready, future URLs pass through immediately.
/// Queued URLs must be drained and reprocessed by the caller.
///
/// ## Usage
///
/// ```swift
/// let queue = DeepLinkReadinessQueue()
///
/// let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(routing)
///     .handler(handler)
///     .middleware(
///         .security(allowedSchemes: ["myapp"]),
///         .readiness(queue: queue)
///     )
///     .build()
///
/// // When the app is ready, drain and reprocess:
/// let pending = queue.markReady()
/// for url in pending {
///     await coordinator.handle(url: url)
/// }
/// ```
public final class ReadinessMiddleware: DeepLinkMiddleware {
	private let queue: any ReadinessQueue
	private let logger = Logger(subsystem: "swift-deep-links", category: "ReadinessMiddleware")

	/// Creates a readiness middleware backed by the given queue.
	///
	/// - Parameter queue: The readiness queue that stores URLs until ready
	public init(queue: any ReadinessQueue) {
		self.queue = queue
	}

	public func intercept(_ url: URL) async throws -> URL? {
		guard let passedURL = queue.enqueue(url) else {
			logger.info("Deep link queued (app not ready): \(url.absoluteString)")
			return nil
		}
		return passedURL
	}
}
