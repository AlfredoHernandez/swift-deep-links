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
/// You can optionally set a maximum queue size to prevent unbounded memory
/// growth. When the limit is reached, the oldest URL is dropped to make
/// room for the new one.
///
/// ```swift
/// let queue = DeepLinkReadinessQueue(maxQueueSize: 50)
/// ```
///
/// ## Thread Safety
///
/// All mutable state is protected by `OSAllocatedUnfairLock`.
/// Safe to call from any thread or actor context.
public final class DeepLinkReadinessQueue: ReadinessQueue, Sendable {
	private let state: OSAllocatedUnfairLock<State>
	private let maxQueueSize: Int?

	private struct State {
		var isReady = false
		var pendingURLs: [URL] = []
	}

	/// Creates a new readiness queue.
	///
	/// - Parameter maxQueueSize: The maximum number of URLs to store.
	///   When the limit is reached, the oldest URL is dropped. Pass `nil`
	///   for unlimited queue size. Defaults to `nil`.
	public init(maxQueueSize: Int? = nil) {
		self.maxQueueSize = maxQueueSize.map { max(1, $0) }
		state = OSAllocatedUnfairLock(initialState: State())
	}

	public var isReady: Bool {
		state.withLock { $0.isReady }
	}

	/// Enqueues the URL if not ready, or returns it for immediate processing.
	///
	/// When `maxQueueSize` is set and the queue is full, the oldest URL
	/// is dropped to make room for the new one.
	///
	/// - Parameter url: The deep link URL
	/// - Returns: The URL if ready (pass through), or `nil` if queued
	public func enqueue(_ url: URL) -> URL? {
		state.withLock { state in
			if state.isReady { return url }
			if let max = maxQueueSize, state.pendingURLs.count >= max {
				state.pendingURLs.removeFirst()
			}
			state.pendingURLs.append(url)
			return nil
		}
	}

	/// Signals readiness and returns all pending URLs for reprocessing.
	///
	/// This method is idempotent — subsequent calls return an empty array.
	///
	/// - Returns: The URLs that were queued before readiness was signaled
	public func markReady() -> [URL] {
		state.withLock { state in
			state.isReady = true
			let pending = state.pendingURLs
			state.pendingURLs = []
			return pending
		}
	}

	/// The number of URLs currently in the queue.
	///
	/// - Returns: The count of URLs waiting to be processed
	public var pendingCount: Int {
		state.withLock { $0.pendingURLs.count }
	}

	/// Resets the queue to its initial not-ready state, discarding any pending URLs.
	///
	/// After calling this method, incoming URLs will be queued again until
	/// ``markReady()`` is called. Useful for scenarios like logout/login cycles
	/// where the app needs to re-gate deep link processing.
	public func reset() {
		state.withLock { state in
			state.isReady = false
			state.pendingURLs = []
		}
	}
}
