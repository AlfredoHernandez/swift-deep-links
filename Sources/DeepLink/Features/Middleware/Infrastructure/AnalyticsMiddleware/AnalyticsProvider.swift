//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import os.log

/// Protocol for analytics providers.
///
/// This protocol defines the interface that analytics providers must implement
/// to send deep link events to different analytics services.
///
/// ## Included Implementations
/// - `DefaultAnalyticsProvider`: Basic implementation that logs to system logs
///
/// ## Common Custom Implementations
/// - Firebase Analytics
/// - Mixpanel
/// - Amplitude
/// - Custom analytics backend
///
/// ## Basic Implementation Example
/// ```swift
/// struct MyAnalyticsProvider: AnalyticsProvider {
///     func track(_ event: String, parameters: [String: Any]) async {
///         // Send to your analytics service
///         await MyAnalyticsService.track(event: event, parameters: parameters)
///     }
/// }
/// ```
///
/// ## Firebase Analytics Example
/// ```swift
/// import FirebaseAnalytics
///
/// struct FirebaseAnalyticsProvider: AnalyticsProvider {
///     func track(_ event: String, parameters: [String: Any]) async {
///         await withCheckedContinuation { continuation in
///             Analytics.logEvent(event, parameters: parameters)
///             continuation.resume()
///         }
///     }
/// }
/// ```
///
/// ## Implementation Considerations
/// - The method must be thread-safe and can be called from any thread
/// - Implementations should handle errors internally
/// - For better performance, consider implementing event batching
/// - Ensure compliance with privacy policies in your implementation
///
/// - SeeAlso: ``AnalyticsMiddleware`` to use this protocol
/// - SeeAlso: ``DefaultAnalyticsProvider`` for a basic implementation
public protocol AnalyticsProvider: Sendable {
    /// Sends an analytics event with parameters.
    ///
    /// - Parameters:
    ///   - event: The name of the event to track (e.g., "deep_link_opened")
    ///   - parameters: Dictionary with the event parameters
    func track(_ event: String, parameters: [String: Any]) async
}

/// Default analytics provider that logs events to system logs.
///
/// This basic implementation of `AnalyticsProvider` logs all analytics events
/// to system logs using `os.log`. It's ideal for development, debugging, and cases
/// where data doesn't need to be sent to external analytics services.
///
/// ## Features
/// - **Integrated logging**: Uses `os.log` for efficient logging
/// - **Configurable**: Allows customizing the logger
/// - **Thread-safe**: Safe for concurrent use
/// - **No external dependencies**: Doesn't require third-party services
///
/// ## Use Cases
/// - **Development and debugging**: See analytics events in real-time
/// - **Simple applications**: When complex analytics isn't needed
/// - **Prototyping**: To quickly test the deep link system
/// - **Local logging**: For log analysis without external services
///
/// ## Basic Usage Example
/// ```swift
/// // Use with default configuration
/// let analyticsProvider = DefaultAnalyticsProvider()
///
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .standard
/// )
/// ```
///
/// ## Custom Logger Example
/// ```swift
/// import os.log
///
/// // Create custom logger for your app
/// let customLogger = Logger(subsystem: "com.myapp.analytics", category: "DeepLinks")
///
/// let customProvider = DefaultAnalyticsProvider(logger: customLogger)
///
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: customProvider,
///     strategy: .detailed
/// )
/// ```
///
/// ## Log Format
/// Events are logged with the following format:
/// ```
/// Analytics: deep_link_opened - url: myApp://product/123, scheme: myApp, host: product, timestamp: 1640995200.0
/// ```
///
/// ## Viewing Logs in Development
/// To view logs in Xcode:
/// 1. Open Xcode console
/// 2. Filter by "DeepLink" or your custom subsystem
/// 3. Run deep links in the simulator
///
/// To view logs on device:
/// ```bash
/// # In terminal, with device connected
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "DeepLink"'
/// ```
///
/// ## Limitations
/// - Logs don't persist indefinitely
/// - No automatic data aggregation
/// - Not suitable for large-scale production analytics
///
/// ## Migration to Production
/// For production, consider implementing a provider that sends data to:
/// - Firebase Analytics
/// - Mixpanel
/// - Your own analytics backend
/// - Logging services like LogRocket or Sentry
///
/// - SeeAlso: ``AnalyticsProvider`` to implement custom providers
/// - SeeAlso: ``AnalyticsMiddleware`` to use this provider
public final class DefaultAnalyticsProvider: AnalyticsProvider {
    private let logger: Logger

    /// Creates a new default analytics provider.
    ///
    /// - Parameter logger: The logger to use for registering events. By default uses
    ///   a logger with subsystem "DeepLink" and category "Analytics".
    ///
    /// ## Example
    /// ```swift
    /// // Use default configuration
    /// let provider = DefaultAnalyticsProvider()
    ///
    /// // With custom logger
    /// let customLogger = Logger(subsystem: "com.myapp", category: "DeepLinks")
    /// let customProvider = DefaultAnalyticsProvider(logger: customLogger)
    /// ```
    public init(logger: Logger = Logger(subsystem: "swift-deep-link", category: "DefaultAnalyticsProvider")) {
        self.logger = logger
    }

    /// Logs an analytics event to system logs.
    ///
    /// - Parameters:
    ///   - event: The name of the event to track
    ///   - parameters: The event parameters
    ///
    /// ## Output Example
    /// For the "deep_link_opened" event with parameters:
    /// ```
    /// Analytics: deep_link_opened - url: myApp://product/123, scheme: myApp, host: product, timestamp: 1640995200.0
    /// ```
    public func track(_ event: String, parameters: [String: Any]) async {
        let parametersString = parameters.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        logger.info("Analytics: \(event) - \(parametersString)")
    }
}
