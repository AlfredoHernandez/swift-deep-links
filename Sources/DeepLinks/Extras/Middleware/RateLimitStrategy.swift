//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Rate limiting strategies for deep links.
///
/// This struct provides different strategies for rate limiting deep link requests,
/// each implementing a different approach to control request frequency and prevent abuse.
///
/// ## Features
/// - **Time window control**: Configurable time windows for rate limiting
/// - **Multiple algorithms**: Sliding window, fixed window, and permissive strategies
/// - **Persistent state**: Rate limiting data persists across app launches
/// - **Thread-safe**: Safe for concurrent use
///
/// ## Available Strategies
/// - `.slidingWindow`: Tracks requests in a rolling time window (recommended for most use cases)
/// - `.fixedWindow`: Uses fixed time windows (e.g., per minute, per hour) for predictable limits
/// - `.tokenBucket(capacity:refillRate:)`: Admits a burst, then a steady refill rate
/// - `.permissive`: Never enforces rate limits (useful for testing or development)
///
/// ## Usage Examples
///
/// ### Sliding Window (Recommended)
/// ```swift
/// let middleware = RateLimitMiddleware(
///     maxRequests: 10,
///     timeWindow: 60.0,
///     strategy: .slidingWindow
/// )
/// ```
///
/// ### Fixed Window
/// ```swift
/// let middleware = RateLimitMiddleware(
///     maxRequests: 100,
///     timeWindow: 3600.0,
///     strategy: .fixedWindow
/// )
/// ```
///
/// ### Testing Mode
/// ```swift
/// let middleware = RateLimitMiddleware(strategy: .permissive)
/// ```
///
/// ## Strategy Comparison
///
/// | Strategy | Time Window | Burst Allowance | Consistency | Use Case |
/// |----------|-------------|-----------------|-------------|----------|
/// | `.slidingWindow` | Rolling | None | High | General purpose |
/// | `.fixedWindow` | Fixed | At boundaries | Medium | Predictable limits |
/// | `.tokenBucket` | Continuous refill | Up to `capacity` | High | Burst-tolerant limits |
/// | `.permissive` | N/A | Unlimited | N/A | Testing/Development |
public struct RateLimitStrategy: Sendable {
	/// Identifies the strategy and its parameters in the default persistence key,
	/// so limiters of different shapes never share stored state.
	let name: String
	private let checkFunction: @Sendable (URL, Int, TimeInterval, RateLimitPersistence, () -> Date) async throws -> URL?

	init(name: String, _ checkFunction: @escaping @Sendable (URL, Int, TimeInterval, RateLimitPersistence, () -> Date) async throws -> URL?) {
		self.name = name
		self.checkFunction = checkFunction
	}

	/// Executes the rate limiting strategy.
	func check(
		url: URL,
		maxRequests: Int,
		timeWindow: TimeInterval,
		persistence: RateLimitPersistence,
		dateProvider: @escaping () -> Date = Date.init,
	) async throws -> URL? {
		try await checkFunction(url, maxRequests, timeWindow, persistence, dateProvider)
	}
}

// MARK: - Rate Limit Strategy Implementations

public extension RateLimitStrategy {
	/// Sliding window rate limiting strategy.
	///
	/// This strategy maintains a rolling time window where requests are tracked continuously.
	/// As time progresses, old requests outside the window are automatically removed,
	/// providing smooth and predictable rate limiting behavior.
	///
	/// ## Use Cases
	/// - General-purpose rate limiting (recommended for most scenarios)
	/// - When you need smooth, continuous rate limiting without sudden resets
	/// - API endpoints that need consistent behavior
	///
	/// ## Example
	/// ```swift
	/// // Allow 10 requests per minute with sliding window
	/// let middleware = RateLimitMiddleware(
	///     maxRequests: 10,
	///     timeWindow: 60.0,
	///     strategy: .slidingWindow
	/// )
	/// ```
	///
	/// ## Behavior
	/// - Tracks all requests in the last `timeWindow` seconds
	/// - Removes expired requests automatically
	/// - Provides consistent rate limiting without burst allowances
	static let slidingWindow = RateLimitStrategy(name: "sliding") { url, maxRequests, timeWindow, persistence, dateProvider in
		let now = dateProvider().timeIntervalSince1970

		let isAdmitted = await persistence.mutateRequests(retaining: timeWindow) { timestamps in
			let validRequests = timestamps.filter { now - $0 <= timeWindow }
			guard validRequests.count < maxRequests else { return false }
			timestamps = validRequests + [now]
			return true
		}

		guard isAdmitted else {
			throw DeepLinkError.rateLimitExceeded(maxRequests: maxRequests, timeWindow: timeWindow)
		}
		return url
	}

	/// Fixed window rate limiting strategy.
	///
	/// This strategy uses fixed time windows where the rate limit resets at predetermined
	/// intervals (e.g., at the start of each minute, hour, or day). This provides
	/// predictable burst allowances but may allow bursts of requests at window boundaries.
	///
	/// ## Use Cases
	/// - When you need predictable rate limit resets (e.g., at the top of each hour)
	/// - Systems that align with business hours or reporting periods
	/// - When burst allowances at window boundaries are acceptable
	///
	/// ## Example
	/// ```swift
	/// // Allow 100 requests per hour, reset at the top of each hour
	/// let middleware = RateLimitMiddleware(
	///     maxRequests: 100,
	///     timeWindow: 3600.0,  // 1 hour
	///     strategy: .fixedWindow
	/// )
	/// ```
	///
	/// ## Behavior
	/// - Creates fixed time windows aligned to the timeWindow interval
	/// - Rate limit resets at window boundaries (e.g., 12:00, 12:01, 12:02...)
	/// - May allow bursts of requests at window transitions
	/// - A zero window only counts requests made at the same instant; an
	///   infinite window never resets
	static let fixedWindow = RateLimitStrategy(name: "fixed") { url, maxRequests, timeWindow, persistence, dateProvider in
		let now = dateProvider()
		let windowStart = fixedWindowStart(containing: now, timeWindow: timeWindow).timeIntervalSince1970
		let instant = now.timeIntervalSince1970

		let isAdmitted = await persistence.mutateRequests(retaining: timeWindow) { timestamps in
			let windowRequests = timestamps.filter { $0 >= windowStart }
			guard windowRequests.count < maxRequests else { return false }
			timestamps = windowRequests + [instant]
			return true
		}

		guard isAdmitted else {
			throw DeepLinkError.rateLimitExceeded(maxRequests: maxRequests, timeWindow: timeWindow)
		}
		return url
	}

	/// Permissive rate limiting strategy.
	///
	/// This strategy never enforces rate limits and always allows requests to pass through.
	/// It's primarily intended for testing, development, or when rate limiting needs to be
	/// conditionally disabled.
	///
	/// ## Use Cases
	/// - Unit testing where rate limiting would interfere with test execution
	/// - Development environments where rate limiting is not needed
	/// - Conditional rate limiting (can be switched at runtime)
	/// - Debugging rate limiting issues
	///
	/// ## Example
	/// ```swift
	/// // For testing - allows all requests
	/// let middleware = RateLimitMiddleware(strategy: .permissive)
	///
	/// // Conditional rate limiting
	/// let strategy: RateLimitStrategy = isProduction ? .slidingWindow : .permissive
	/// let middleware = RateLimitMiddleware(
	///     maxRequests: 100,
	///     timeWindow: 60.0,
	///     strategy: strategy
	/// )
	/// ```
	///
	/// ## Behavior
	/// - Always returns the original URL without any checks
	/// - No persistence operations are performed
	/// - No performance overhead from rate limiting logic
	/// - Thread-safe (no concurrent access needed)
	static let permissive = RateLimitStrategy(name: "permissive") { url, _, _, _, _ in
		url
	}

	/// Token bucket rate limiting strategy.
	///
	/// The bucket holds up to `capacity` tokens and gains `refillRate` tokens
	/// per second. Each request spends one token; a request that finds the
	/// bucket empty throws ``DeepLinkError/rateLimitExceeded(maxRequests:timeWindow:)``
	/// carrying `capacity` and the time a full refill takes. Unlike the window
	/// strategies, it tolerates a burst of `capacity` links and then settles to
	/// a steady rate.
	///
	/// The middleware's `maxRequests` and `timeWindow` are ignored; the bucket
	/// is configured entirely by this factory. The state is a single timestamp
	/// in the middleware's ``RateLimitPersistence``, so it survives relaunches
	/// with ``UserDefaultsRateLimitPersistence`` and is serialized by the
	/// middleware like the other strategies.
	///
	/// ## Example
	/// ```swift
	/// // Allow a burst of 10 links, then one every 2 seconds
	/// let middleware = RateLimitMiddleware(
	///     strategy: .tokenBucket(capacity: 10, refillRate: 0.5)
	/// )
	/// ```
	///
	/// ## Behavior
	/// - A `capacity` of `0` or less rejects every request
	/// - A `refillRate` of `0`, negative or NaN never refills: only `capacity`
	///   requests are ever admitted (until the persistence prunes them), and the
	///   error's `timeWindow` is the time since the first admitted request
	/// - An infinite `refillRate` never limits
	/// - If the clock moves backwards, the wait is capped at one full refill
	///
	/// - Parameters:
	///   - capacity: The maximum number of tokens, which is the largest burst admitted at once.
	///   - refillRate: Tokens added per second.
	/// - Returns: A token bucket strategy.
	static func tokenBucket(capacity: Int, refillRate: Double) -> RateLimitStrategy {
		let bucket = TokenBucket(capacity: capacity, refillRate: refillRate)
		return RateLimitStrategy(name: "bucket.\(bucket.capacity).\(bucket.refillRate)") { url, _, _, persistence, dateProvider in
			let now = dateProvider().timeIntervalSince1970

			let outcome = await persistence.mutateRequests { state in
				let outcome = bucket.consume(at: now, state: state)
				state = outcome.state
				return outcome
			}

			guard outcome.isAdmitted else {
				throw bucket.exceededError(at: now, state: outcome.state)
			}
			return url
		}
	}
}

// MARK: - Fixed Window Boundaries

private func fixedWindowStart(containing now: Date, timeWindow: TimeInterval) -> Date {
	guard timeWindow > 0 else { return now }
	guard timeWindow.isFinite else { return .distantPast }
	return Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / timeWindow) * timeWindow)
}
