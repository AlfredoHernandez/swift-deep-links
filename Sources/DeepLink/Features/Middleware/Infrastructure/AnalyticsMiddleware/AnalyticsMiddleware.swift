//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware for deep link analytics tracking.
///
/// This middleware intercepts all deep link URLs and sends them to an analytics provider
/// using a configurable strategy. It allows tracking deep link usage for user behavior
/// analysis and engagement metrics.
///
/// ## Features
/// - **Automatic interception**: Automatically tracks all processed URLs
/// - **Configurable strategies**: Different levels of detail in tracking
/// - **Flexible providers**: Compatible with any analytics provider
/// - **Non-blocking flow**: The middleware doesn't interrupt normal deep link processing
///
/// ## Use Cases
/// - Track which deep links are most used
/// - Analyze user navigation patterns
/// - Measure marketing campaign effectiveness
/// - Monitor deep link performance
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// // Create an analytics provider
/// let analyticsProvider = DefaultAnalyticsProvider(
///     logger: Logger(subsystem: "MyApp", category: "DeepLinks")
/// )
///
/// // Create middleware with standard strategy
/// let analyticsMiddleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .standard
/// )
///
/// // Add to deep link coordinator
/// let coordinator = DeepLinkCoordinator.builder()
///     .addMiddleware(analyticsMiddleware)
///     .build()
/// ```
///
/// ### Custom Strategy
/// ```swift
/// // For deeper analysis, use detailed strategy
/// let detailedAnalyticsMiddleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .detailed
/// )
/// ```
///
/// ### Custom Provider
/// ```swift
/// struct MyAnalyticsProvider: AnalyticsProvider {
///     func track(_ event: String, parameters: [String: Any]) async {
///         // Send to Firebase Analytics, Mixpanel, etc.
///         await FirebaseAnalytics.track(event: event, parameters: parameters)
///     }
/// }
///
/// let customAnalyticsMiddleware = AnalyticsMiddleware(
///     analyticsProvider: MyAnalyticsProvider(),
///     strategy: .performance
/// )
/// ```
///
/// ## Available Strategies
/// - `.standard`: Tracks basic information (URL, scheme, host, timestamp)
/// - `.detailed`: Includes path and query parameters
/// - `.minimal`: Only essential information (scheme, host, timestamp)
/// - `.performance`: Includes processing time metrics
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
///
/// - SeeAlso: ``AnalyticsStrategy`` for more information about available strategies
/// - SeeAlso: ``AnalyticsProvider`` for implementing custom providers
public final class AnalyticsMiddleware: DeepLinkMiddleware {
    private let analyticsProvider: AnalyticsProvider
    private let strategy: AnalyticsStrategy

    /// Creates a new analytics middleware.
    ///
    /// - Parameters:
    ///   - analyticsProvider: The analytics provider to use for sending events.
    ///     Can be a custom provider or the included `DefaultAnalyticsProvider`.
    ///   - strategy: The tracking strategy to use. Defaults to `.standard`.
    ///     See ``AnalyticsStrategy`` for available options.
    public init(
        analyticsProvider: AnalyticsProvider,
        strategy: AnalyticsStrategy = .standard,
    ) {
        self.analyticsProvider = analyticsProvider
        self.strategy = strategy
    }

    /// Intercepts a deep link URL for analytics tracking.
    ///
    /// This method is automatically called by the deep link coordinator when processing
    /// a URL. It tracks the URL using the configured strategy and then allows normal
    /// processing to continue.
    ///
    /// - Parameter url: The deep link URL to track
    /// - Returns: The same URL to allow continued processing, or `nil` if it should be cancelled
    /// - Throws: Does not throw errors in the current implementation
    public func intercept(_ url: URL) async throws -> URL? {
        await strategy.track(url: url, provider: analyticsProvider)
        return url
    }
}
