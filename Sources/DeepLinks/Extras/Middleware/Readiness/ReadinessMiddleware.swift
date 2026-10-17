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
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(routing)
///     .handler(handler)
///     .middleware(
///         .security(allowedSchemes: ["myapp"]),
///         .readiness(queue: queue)
///     )
///     .build()
///
/// // When the app is ready, drain and reprocess — each URL resumes the
/// // chain after this middleware, so middleware before it does not fire
/// // twice and middleware after it evaluates the link at drain time:
/// await coordinator.markReadyAndDrain(queue: queue)
/// ```
///
/// If you drive a ``DeepLinkMiddlewareCoordinator`` without a coordinator,
/// call ``ReadinessQueue/markReadyReturningRequests()`` and feed each request
/// through ``DeepLinkMiddlewareCoordinator/process(_:startingAfter:)`` with this
/// middleware as the anchor. Never feed ``ReadinessQueue/markReady()`` URLs to
/// ``DeepLinkCoordinator/handle(url:)``: they were already rewritten by the
/// middleware before this one (signature parameters removed), so the whole
/// chain runs again on them and signed links fail as unsigned.
public final class ReadinessMiddleware: DeepLinkMiddleware, ChainGate {
	private let queue: any ReadinessQueue
	private let log: LoggingProvider
	private let privacy: DeepLinkLogPrivacy

	/// Creates a readiness middleware backed by the given queue.
	///
	/// - Parameters:
	///   - queue: The readiness queue that stores URLs until ready
	///   - privacy: How the queued-link log describes the URL. Defaults to ``DeepLinkLogPrivacy/redacted``.
	public convenience init(queue: any ReadinessQueue, privacy: DeepLinkLogPrivacy = .redacted) {
		self.init(
			queue: queue,
			privacy: privacy,
			log: .systemLogger(Logger(subsystem: "swift-deep-links", category: "ReadinessMiddleware")),
		)
	}

	init(queue: any ReadinessQueue, privacy: DeepLinkLogPrivacy = .redacted, log: LoggingProvider) {
		self.queue = queue
		self.privacy = privacy
		self.log = log
	}

	/// Queues `request` until the queue is ready, stopping the chain, or
	/// passes it through once ready.
	///
	/// A queued link is resumed right after this middleware by
	/// ``DeepLinkCoordinator/markReadyAndDrain(queue:)``; middleware before it
	/// does not run again.
	///
	/// - Returns: `request` when ready, `nil` when queued.
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard let passed = queue.enqueue(request) else {
			log.log(level: .info, "Deep link queued (app not ready): \(privacy.describe(request.url))")
			return nil
		}
		return passed
	}

	func isGating(_ candidate: any ReadinessQueue) -> Bool {
		(queue as AnyObject) === (candidate as AnyObject)
	}
}
