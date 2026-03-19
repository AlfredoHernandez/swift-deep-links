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
	/// - Returns: The URLs that were queued before readiness was signaled
	func markReady() -> [URL]

	/// The number of URLs currently in the queue.
	///
	/// - Returns: The count of URLs waiting to be processed
	var pendingCount: Int { get }

	/// Resets the queue to its initial not-ready state, discarding any pending URLs.
	func reset()
}
