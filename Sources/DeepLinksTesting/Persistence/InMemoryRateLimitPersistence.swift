//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// An in-memory implementation of `RateLimitPersistence` that stores timestamps without any disk persistence.
///
/// `InMemoryRateLimitPersistence` maintains request timestamps in memory, making it ideal for testing
/// rate-limiting functionality. Thread safety is guaranteed through actor isolation.
/// All request data is lost when the actor is deallocated.
///
/// ## Overview
///
/// Create an in-memory persistence store and use it with rate-limit middleware:
///
///     let persistence = InMemoryRateLimitPersistence()
///     let middleware = RateLimitMiddleware(
///         maxRequests: 5,
///         timeWindow: 60,
///         persistence: persistence
///     )
///
/// ## Testing Rate Limit Behavior
///
/// Verify that rate limiting correctly allows and blocks requests:
///
///     let persistence = InMemoryRateLimitPersistence()
///     let middleware = RateLimitMiddleware(
///         maxRequests: 2,
///         timeWindow: 60,
///         persistence: persistence
///     )
///
///     let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///         .routing(routing)
///         .handler(handler)
///         .build()
///
///     await coordinator.add(middleware)
///
///     // First two requests should succeed
///     await coordinator.handle(url: url1)
///     await coordinator.handle(url: url2)
///
///     // Third request should be rate limited
///     await coordinator.handle(url: url3)
///
/// - Note: All data is stored in memory and will be lost when the actor is deallocated. Use for testing only.
/// - Thread Safety: This type is an actor and is safe to use concurrently from any thread.
/// - SeeAlso: `RateLimitPersistence`
public actor InMemoryRateLimitPersistence: RateLimitPersistence {
	private var timestamps: [TimeInterval] = []

	/// Initializes a new empty in-memory persistence store.
	public init() {}

	/// Retrieves all stored request timestamps.
	///
	/// - Returns: An array of timestamps representing when requests were recorded, in chronological order.
	public func loadRequests() -> [TimeInterval] {
		timestamps
	}

	/// Saves the given request timestamps, replacing any previously stored timestamps.
	///
	/// - Parameter timestamps: The timestamps to store for rate limit tracking.
	public func saveRequests(_ timestamps: [TimeInterval]) {
		self.timestamps = timestamps
	}

	/// Removes all stored request timestamps.
	///
	/// Use this to reset the rate limit state during testing or between test cases.
	public func clearRequests() {
		timestamps.removeAll()
	}
}
