//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware for rate limiting deep link requests.
///
/// This middleware prevents abuse by limiting the number of deep link requests
/// within a specified time window. The rate limiting state persists across app launches.
///
/// ## Features
/// - **Configurable limits**: Set maximum requests per time window
/// - **Multiple strategies**: Different rate limiting approaches
/// - **Persistent state**: Rate limiting data persists across app launches
/// - **Thread-safe**: Safe for concurrent use
///
/// ## Use Cases
/// - Prevent deep link abuse and spam
/// - Protect against malicious or excessive usage
/// - Implement fair usage policies
/// - Control resource consumption
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// // Basic usage with sliding window strategy
/// let middleware = RateLimitMiddleware(
///     maxRequests: 10,
///     timeWindow: 60.0  // 10 requests per minute
/// )
/// ```
///
/// ### Fixed Window Strategy
/// ```swift
/// // Custom configuration with fixed window strategy
/// let middleware = RateLimitMiddleware(
///     maxRequests: 100,
///     timeWindow: 3600.0,  // 100 requests per hour
///     strategy: .fixedWindow
/// )
/// ```
///
/// ### Testing Configuration
/// ```swift
/// // For testing with in-memory persistence
/// let testPersistence = InMemoryRateLimitPersistence()
/// let middleware = RateLimitMiddleware(
///     maxRequests: 5,
///     timeWindow: 60.0,
///     persistence: testPersistence,
///     strategy: .permissive  // Allows all requests for testing
/// )
/// ```
///
/// ## Available Strategies
/// - `.slidingWindow`: Tracks requests in a rolling time window (recommended for most use cases)
/// - `.fixedWindow`: Uses fixed time windows (e.g., per minute, per hour) for predictable limits
/// - `.tokenBucket(capacity:refillRate:)`: Admits a burst, then a steady refill rate
/// - `.permissive`: Never enforces rate limits (useful for testing or development)
///
/// ## Error Handling
/// When rate limits are exceeded, the middleware throws `DeepLinkError.rateLimitExceeded`
/// which can be handled by your error handling logic.
///
/// ## Thread Safety
/// This middleware is safe to use concurrently. Each instance serializes the
/// check-and-record step, so N simultaneous links against a limit of K admit
/// exactly K. Separate instances sharing one persistence are atomic too,
/// because every strategy records through
/// ``RateLimitPersistence/mutateRequests(_:)``.
public final class RateLimitMiddleware: DeepLinkMiddleware {
	private let maxRequests: Int
	private let timeWindow: TimeInterval
	let persistence: RateLimitPersistence
	private let strategy: RateLimitStrategy
	private let dateProvider: @Sendable () -> Date
	private let gate = AsyncSerialGate()

	/// Creates a new rate limit middleware.
	///
	/// - Parameters:
	///   - maxRequests: Maximum number of requests allowed in the time window. Must be greater than 0.
	///   - timeWindow: Time window in seconds. Negative and NaN values are
	///     treated as `0`, which only counts requests made at the same instant.
	///   - persistence: Persistence mechanism for storing request data (defaults to
	///     ``UserDefaultsRateLimitPersistence/shared(key:)``, shared by every rate limiter using the default)
	///   - strategy: The rate limiting strategy to use (defaults to .slidingWindow)
	///   - dateProvider: Supplies the current time for rate-limit bookkeeping.
	///     Defaults to `Date.init`; inject a deterministic provider in tests to
	///     avoid real-time sleeps.
	///
	/// ## Examples
	///
	/// ```swift
	/// // Allow 10 requests per minute
	/// let middleware = RateLimitMiddleware(maxRequests: 10, timeWindow: 60.0)
	///
	/// // Allow 100 requests per hour with fixed windows
	/// let middleware = RateLimitMiddleware(
	///     maxRequests: 100,
	///     timeWindow: 3600.0,
	///     strategy: .fixedWindow
	/// )
	///
	/// // For testing - allows all requests
	/// let middleware = RateLimitMiddleware(strategy: .permissive)
	///
	/// // Deterministic time in tests
	/// let now = Date(timeIntervalSince1970: 1_700_000_000)
	/// let middleware = RateLimitMiddleware(
	///     maxRequests: 3,
	///     timeWindow: 60,
	///     dateProvider: { now }
	/// )
	/// ```
	public init(
		maxRequests: Int = 100,
		timeWindow: TimeInterval = 60.0,
		persistence: RateLimitPersistence = UserDefaultsRateLimitPersistence.shared(),
		strategy: RateLimitStrategy = .slidingWindow,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.maxRequests = max(maxRequests, 0)
		self.timeWindow = timeWindow.isNaN ? 0 : Swift.max(timeWindow, 0)
		self.persistence = persistence
		self.strategy = strategy
		self.dateProvider = dateProvider
	}

	/// Intercepts a deep link URL and applies rate limiting.
	///
	/// This method checks if the request is within the configured rate limits.
	/// If the limit is exceeded, it throws a `DeepLinkError.rateLimitExceeded` error.
	/// Otherwise, it returns the original URL to allow processing to continue.
	///
	/// - Parameter url: The deep link URL to process
	/// - Returns: The original URL if within rate limits
	/// - Throws: `DeepLinkError.rateLimitExceeded` if the rate limit is exceeded,
	///   or `CancellationError` if the task is cancelled before its turn, in
	///   which case no budget is consumed
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		let url = request.url
		let checked = try await gate.run { [strategy, maxRequests, timeWindow, persistence, dateProvider] in
			try await strategy.check(
				url: url,
				maxRequests: maxRequests,
				timeWindow: timeWindow,
				persistence: persistence,
				dateProvider: dateProvider,
			)
		}
		return checked.map(request.replacingURL)
	}
}
