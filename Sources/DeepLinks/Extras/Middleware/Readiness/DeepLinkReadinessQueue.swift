//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// A queue that stores deep link URLs until a readiness condition is met.
///
/// When deep links arrive before the app is ready, they are stored
/// in an internal queue. Once ``markReady()`` is called, the queued
/// URLs are returned for reprocessing through the coordinator.
///
/// ## Usage
///
/// ```swift
/// let queue = DeepLinkReadinessQueue()
///
/// // In the middleware stack — URLs are queued if not ready
/// .readiness(queue: queue)
///
/// // When the app is ready (e.g., initial UI settled)
/// let pending = queue.markReady()
/// for url in pending {
///     await coordinator.handle(url: url)
/// }
/// ```
///
/// ## Queue Size Limit
///
/// The queue holds at most ``defaultMaxQueueSize`` (50) URLs by default.
/// When the limit is reached, the oldest URL is dropped to make room for the
/// new one; pass `onEvict` to observe dropped links.
///
/// ```swift
/// let queue = DeepLinkReadinessQueue(maxQueueSize: 20) { evicted in
///     logger.warning("Dropped queued deep link for \(evicted.host() ?? "?")")
/// }
/// ```
///
/// `maxQueueSize: nil` makes the queue unbounded, which lets any app or web
/// page grow memory by firing links before your app is ready.
///
/// ## Thread Safety
///
/// All mutable state is protected by `OSAllocatedUnfairLock`.
/// Safe to call from any thread or actor context.
public final class DeepLinkReadinessQueue: ReadinessQueue, Sendable {
	private let state: OSAllocatedUnfairLock<State>
	private let maxQueueSize: Int?
	private let onEvict: (@Sendable (URL) -> Void)?

	/// The queue size used when none is given.
	public static let defaultMaxQueueSize = 50

	private struct State {
		var isReady = false
		var pending: [DeepLinkRequest] = []
	}

	/// Creates a new readiness queue.
	///
	/// - Parameters:
	///   - maxQueueSize: The maximum number of URLs to store.
	///     When the limit is reached, the oldest URL is dropped. Pass `nil`
	///     for unlimited queue size. Defaults to ``defaultMaxQueueSize``.
	///   - onEvict: Called with each URL dropped to make room, after the queue
	///     lock is released, on the thread that enqueued the new URL.
	///     Defaults to `nil`.
	public init(maxQueueSize: Int? = defaultMaxQueueSize, onEvict: (@Sendable (URL) -> Void)? = nil) {
		self.maxQueueSize = maxQueueSize.map { max(1, $0) }
		self.onEvict = onEvict
		state = OSAllocatedUnfairLock(initialState: State())
	}

	/// Whether links pass through instead of being queued: `false` until
	/// ``markReady()`` or ``markReadyReturningRequests()``, and again after ``reset()``.
	public var isReady: Bool {
		state.withLock { $0.isReady }
	}

	/// Enqueues the URL if not ready, or returns it for immediate processing.
	///
	/// When `maxQueueSize` is set and the queue is full, the oldest URL
	/// is dropped to make room for the new one and reported to `onEvict`.
	///
	/// - Parameter url: The deep link URL
	/// - Returns: The URL if ready (pass through), or `nil` if queued
	public func enqueue(_ url: URL) -> URL? {
		enqueue(DeepLinkRequest(url: url))?.url
	}

	/// Queues `request`, with its context, while not ready; returns it unchanged once ready.
	///
	/// When the queue is full the oldest link is dropped: a signed link it
	/// reserved is released, and `onEvict` receives its URL after the lock is
	/// released.
	///
	/// - Returns: `request` when ready, `nil` when it was queued.
	public func enqueue(_ request: DeepLinkRequest) -> DeepLinkRequest? {
		let outcome = state.withLock { state -> (passThrough: DeepLinkRequest?, evicted: DeepLinkRequest?) in
			if state.isReady {
				return (request, nil)
			}
			var evicted: DeepLinkRequest?
			if let max = maxQueueSize, state.pending.count >= max {
				evicted = state.pending.removeFirst()
			}
			state.pending.append(request)
			return (nil, evicted)
		}
		if let evicted = outcome.evicted {
			evicted.deferral?.settleDropped()
			onEvict?(evicted.url)
		}
		return outcome.passThrough
	}

	/// Marks the queue ready and returns the queued URLs, oldest first,
	/// emptying the queue. Calling it again returns an empty array. Prefer
	/// ``DeepLinkCoordinator/markReadyAndDrain(queue:)``, which also routes them.
	public func markReady() -> [URL] {
		markReadyReturningRequests().map(\.url)
	}

	/// Marks the queue ready and returns the queued requests with their
	/// contexts, oldest first, emptying the queue atomically: a link enqueued
	/// concurrently is either returned here or passed through, never lost.
	public func markReadyReturningRequests() -> [DeepLinkRequest] {
		state.withLock { state in
			state.isReady = true
			defer { state.pending = [] }
			return state.pending
		}
	}

	/// The number of URLs currently in the queue.
	///
	/// - Returns: The count of URLs waiting to be processed
	public var pendingCount: Int {
		state.withLock { $0.pending.count }
	}

	/// A snapshot of the URLs currently in the queue.
	///
	/// Unlike ``markReady()``, reading this property does not drain the queue,
	/// so it is safe to use for recovery or inspection without losing URLs.
	///
	/// - Returns: The URLs currently waiting to be processed
	public var pendingURLs: [URL] {
		pendingRequests.map(\.url)
	}

	/// A snapshot of the queued requests with their contexts, oldest first;
	/// reading it does not drain the queue.
	public var pendingRequests: [DeepLinkRequest] {
		state.withLock { $0.pending }
	}

	/// Resets the queue to its initial not-ready state, discarding any pending URLs.
	///
	/// After calling this method, incoming URLs will be queued again until
	/// ``markReady()`` is called. Useful for scenarios like logout/login cycles
	/// where the app needs to re-gate deep link processing.
	public func reset() {
		let dropped = state.withLock { state in
			state.isReady = false
			defer { state.pending = [] }
			return state.pending
		}
		dropped.forEach { $0.deferral?.settleDropped() }
	}
}
