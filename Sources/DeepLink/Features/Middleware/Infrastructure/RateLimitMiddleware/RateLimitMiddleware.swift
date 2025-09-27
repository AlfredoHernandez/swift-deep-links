//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - `.permissive`: Never enforces rate limits (useful for testing or development)
///
/// ## Error Handling
/// When rate limits are exceeded, the middleware throws `DeepLinkError.rateLimitExceeded`
/// which can be handled by your error handling logic.
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently. All operations
/// are performed on the provided dispatch queue with appropriate barriers for
/// write operations.
public final class RateLimitMiddleware: DeepLinkMiddleware {
    private let maxRequests: Int
    private let timeWindow: TimeInterval
    private let persistence: RateLimitPersistence
    private let queue: DispatchQueue
    private let strategy: RateLimitStrategy

    /// Creates a new rate limit middleware.
    ///
    /// - Parameters:
    ///   - maxRequests: Maximum number of requests allowed in the time window. Must be greater than 0.
    ///   - timeWindow: Time window in seconds. Must be greater than 0.
    ///   - persistence: Persistence mechanism for storing request data (defaults to UserDefaults-based persistence)
    ///   - queue: DispatchQueue for thread-safe operations (defaults to a new concurrent queue)
    ///   - strategy: The rate limiting strategy to use (defaults to .slidingWindow)
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
    /// ```
    public init(
        maxRequests: Int = 100,
        timeWindow: TimeInterval = 60.0,
        persistence: RateLimitPersistence = UserDefaultsRateLimitPersistence(),
        queue: DispatchQueue = DispatchQueue(label: "io.alfredodhz.deeplink.rate-limit", attributes: .concurrent),
        strategy: RateLimitStrategy = .slidingWindow,
    ) {
        self.maxRequests = maxRequests
        self.timeWindow = timeWindow
        self.persistence = persistence
        self.queue = queue
        self.strategy = strategy
    }

    /// Intercepts a deep link URL and applies rate limiting.
    ///
    /// This method checks if the request is within the configured rate limits.
    /// If the limit is exceeded, it throws a `DeepLinkError.rateLimitExceeded` error.
    /// Otherwise, it returns the original URL to allow processing to continue.
    ///
    /// - Parameter url: The deep link URL to process
    /// - Returns: The original URL if within rate limits
    /// - Throws: `DeepLinkError.rateLimitExceeded` if the rate limit is exceeded
    public func intercept(_ url: URL) async throws -> URL? {
        try await strategy.check(
            url: url,
            maxRequests: maxRequests,
            timeWindow: timeWindow,
            persistence: persistence,
            queue: queue,
            dateProvider: Date.init,
        )
    }
}
