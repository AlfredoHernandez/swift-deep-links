//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// An in-memory implementation of `RateLimitPersistence` that stores
/// timestamps without any disk persistence.
///
/// Thread safety is guaranteed by actor isolation.
///
/// ```swift
/// let persistence = InMemoryRateLimitPersistence()
/// let middleware = RateLimitMiddleware(
///     maxRequests: 5,
///     timeWindow: 60,
///     persistence: persistence
/// )
/// ```
public actor InMemoryRateLimitPersistence: RateLimitPersistence {
	private var timestamps: [TimeInterval] = []

	public init() {}

	public func loadRequests() -> [TimeInterval] {
		timestamps
	}

	public func saveRequests(_ timestamps: [TimeInterval]) {
		self.timestamps = timestamps
	}

	public func clearRequests() {
		timestamps.removeAll()
	}
}
