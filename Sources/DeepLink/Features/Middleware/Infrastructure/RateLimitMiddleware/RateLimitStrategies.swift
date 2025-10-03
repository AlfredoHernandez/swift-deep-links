//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// | `.permissive` | N/A | Unlimited | N/A | Testing/Development |
public struct RateLimitStrategy: Sendable {
    private let checkFunction: @Sendable (URL, Int, TimeInterval, RateLimitPersistence, () -> Date) async throws -> URL?

    init(_ checkFunction: @escaping @Sendable (URL, Int, TimeInterval, RateLimitPersistence, () -> Date) async throws -> URL?) {
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
    static let slidingWindow = RateLimitStrategy { url, maxRequests, timeWindow, persistence, dateProvider in
        let now = dateProvider()

        // Load existing requests from persistence
        let timestamps = await persistence.loadRequests()
        let requests = timestamps.map { Date(timeIntervalSince1970: $0) }

        // Remove old requests outside the time window
        let validRequests = requests.filter { now.timeIntervalSince($0) <= timeWindow }

        // Check if we're within the rate limit
        if validRequests.count >= maxRequests {
            throw DeepLinkError.rateLimitExceeded(maxRequests, timeWindow)
        }

        // Add current request
        let updatedTimestamps = validRequests.map(\.timeIntervalSince1970) + [now.timeIntervalSince1970]
        await persistence.saveRequests(updatedTimestamps)

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
    static let fixedWindow = RateLimitStrategy { url, maxRequests, timeWindow, persistence, dateProvider in
        let now = dateProvider()
        let windowStart = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / timeWindow) * timeWindow)

        // Load existing requests from persistence
        let timestamps = await persistence.loadRequests()
        let requests = timestamps.map { Date(timeIntervalSince1970: $0) }

        // Filter requests within the current window
        let windowRequests = requests.filter { $0 >= windowStart }

        // Check if we're within the rate limit
        if windowRequests.count >= maxRequests {
            throw DeepLinkError.rateLimitExceeded(maxRequests, timeWindow)
        }

        // Add current request
        let updatedTimestamps = windowRequests.map(\.timeIntervalSince1970) + [now.timeIntervalSince1970]
        await persistence.saveRequests(updatedTimestamps)

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
    static let permissive = RateLimitStrategy { url, _, _, _, _ in
        url
    }
}
