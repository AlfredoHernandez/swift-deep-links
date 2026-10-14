//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Token-bucket arithmetic over a single persisted timestamp: the instant at
/// which the bucket will be full again (the GCRA formulation). Storing one
/// timestamp keeps the state compatible with ``RateLimitPersistence``.
struct TokenBucket: Sendable {
	private static let relativeTolerance = 1e-9

	let capacity: Int
	let refillRate: Double

	init(capacity: Int, refillRate: Double) {
		self.capacity = max(capacity, 0)
		let rate = refillRate.isNaN ? 0 : max(refillRate, 0)
		self.refillRate = rate.isInfinite || (1 / rate).isFinite ? rate : 0
	}

	/// The error for a rejected request. A bucket that never refills has no
	/// refill time, so it reports how long ago its first admitted request was.
	func exceededError(at now: TimeInterval, state: [TimeInterval]) -> DeepLinkError {
		guard refillRate > 0 else {
			let span = state.min().map { max(now - $0, 0) } ?? 0
			return .rateLimitExceeded(maxRequests: capacity, timeWindow: span)
		}
		return .rateLimitExceeded(maxRequests: capacity, timeWindow: Double(capacity) / refillRate)
	}

	/// Spends one token at `now`. The returned state is what to persist:
	/// unchanged when nothing moved, or re-anchored when the clock went
	/// backwards past the stored state, so the wait never exceeds one full
	/// refill even across rejected requests.
	func consume(at now: TimeInterval, state: [TimeInterval]) -> (isAdmitted: Bool, state: [TimeInterval]) {
		guard capacity > 0 else { return (false, state) }
		guard refillRate > 0 else {
			return state.count < capacity ? (true, state + [now]) : (false, state)
		}
		guard refillRate.isFinite else { return (true, [now]) }

		let refillInterval = 1 / refillRate
		let burstSpan = Double(capacity) * refillInterval
		let storedFullAt = state.max() ?? now
		let fullAt = min(max(storedFullAt, now), now + burstSpan)
		let nextFullAt = fullAt + refillInterval

		guard nextFullAt - now <= burstSpan * (1 + Self.relativeTolerance) else {
			return (false, fullAt < storedFullAt ? [fullAt] : state)
		}
		return (true, [nextFullAt])
	}
}
