//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A readiness condition backed by a queue that stores deep links until ready.
///
/// Conforming types must provide queue management capabilities in addition
/// to the basic `isReady` check from ``ReadinessCondition``.
///
/// ## Built-in Implementations
///
/// - ``DeepLinkReadinessQueue``: A thread-safe, lock-based queue with
///   optional max size and reset support.
public protocol ReadinessQueue: ReadinessCondition {
	/// Enqueues the URL if not ready, or returns it for immediate processing.
	///
	/// - Parameter url: The deep link URL
	/// - Returns: The URL if ready (pass through), or `nil` if queued
	func enqueue(_ url: URL) -> URL?

	/// Signals readiness and returns all pending URLs for reprocessing.
	///
	/// - Important: Prefer ``DeepLinkCoordinator/markReadyAndDrain(queue:)``.
	///   The URLs are the ones the readiness gate received, **after** the
	///   middleware before it ran (a signed link already has its signature
	///   parameters removed), and what that middleware holds for them is not
	///   settled (a signed link's nonce stays reserved until it lapses). Passing
	///   them to ``DeepLinkCoordinator/handle(url:)`` runs the whole chain again
	///   on the rewritten URL: signed links then fail as unsigned, replay
	///   protection can drop them as repeats, the rate limit counts them twice,
	///   and their source is lost.
	///
	/// - Returns: The URLs that were queued before readiness was signaled
	func markReady() -> [URL]

	/// The number of URLs currently in the queue.
	///
	/// - Returns: The count of URLs waiting to be processed
	var pendingCount: Int { get }

	/// A snapshot of the URLs currently in the queue.
	///
	/// Unlike ``markReady()``, reading this property does not drain the queue,
	/// so it is safe to use for recovery or inspection without losing URLs.
	///
	/// - Returns: The URLs currently waiting to be processed
	var pendingURLs: [URL] { get }

	/// Resets the queue to its initial not-ready state, discarding any pending URLs.
	func reset()

	/// Enqueues the request if not ready, or returns it for immediate processing.
	///
	/// Keeping the whole request lets a drained link reach the handler with
	/// the ``DeepLinkContext`` it arrived with. The default enqueues the URL,
	/// so a queue implementing only ``enqueue(_:)-(URL)`` drains with
	/// ``DeepLinkContext/unknown``.
	///
	/// - Parameter request: The deep link and its context
	/// - Returns: The request if ready (pass through), or `nil` if queued
	func enqueue(_ request: DeepLinkRequest) -> DeepLinkRequest?

	/// Signals readiness and returns all pending requests, with their
	/// contexts, for reprocessing. The default wraps ``markReady()``.
	func markReadyReturningRequests() -> [DeepLinkRequest]

	/// A snapshot of the requests currently in the queue. The default wraps ``pendingURLs``.
	var pendingRequests: [DeepLinkRequest] { get }
}

public extension ReadinessQueue {
	/// Enqueues only `request.url`; a queued link drains with
	/// ``DeepLinkContext/unknown``. A link passed through while ready keeps its context.
	func enqueue(_ request: DeepLinkRequest) -> DeepLinkRequest? {
		enqueue(request.url).map(request.replacingURL)
	}

	/// Wraps ``markReady()``; every request carries ``DeepLinkContext/unknown``.
	func markReadyReturningRequests() -> [DeepLinkRequest] {
		markReady().map { DeepLinkRequest(url: $0) }
	}

	/// Wraps ``pendingURLs``; every request carries ``DeepLinkContext/unknown``.
	var pendingRequests: [DeepLinkRequest] {
		pendingURLs.map { DeepLinkRequest(url: $0) }
	}
}
