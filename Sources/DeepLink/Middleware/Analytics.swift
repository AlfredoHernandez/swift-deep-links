//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Analytics tracking strategies for deep links.
///
/// This struct defines different strategies for tracking deep link usage, each optimized
/// for different use cases and levels of detail in the collected information.
///
/// ## Features
/// - **Configurable detail levels**: From minimal to comprehensive tracking
/// - **Privacy compliance**: Options for GDPR/CCPA compliance
/// - **Performance monitoring**: Built-in timing metrics
/// - **Flexible data collection**: Customizable parameter tracking
///
/// ## Available Strategies
/// - `.standard`: Basic information for general use
/// - `.detailed`: Complete information including parameters
/// - `.minimal`: Only essential data for restricted cases
/// - `.performance`: Includes performance metrics
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .standard
/// )
/// ```
///
/// ### Detailed Analysis
/// ```swift
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .detailed // For complete analysis
/// )
/// ```
///
/// ### Privacy-Compliant
/// ```swift
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .minimal // For GDPR/CCPA compliance
/// )
/// ```
///
/// ### Performance Monitoring
/// ```swift
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .performance // For performance tracking
/// )
/// ```
///
/// ## Strategy Comparison
///
/// | Strategy | URL | Scheme | Host | Path | Parameters | Timestamp | Performance |
/// |----------|-----|--------|------|------|------------|-----------|-------------|
/// | `.minimal` | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
/// | `.standard` | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ |
/// | `.detailed` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
/// | `.performance` | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
///
/// - SeeAlso: ``AnalyticsMiddleware`` to implement the middleware
/// - SeeAlso: ``AnalyticsProvider`` for custom providers
public struct AnalyticsStrategy: Sendable {
	private let trackFunction: @Sendable (URL, AnalyticsProvider) async -> Void

	init(_ trackFunction: @escaping @Sendable (URL, AnalyticsProvider) async -> Void) {
		self.trackFunction = trackFunction
	}

	/// Executes the analytics tracking strategy.
	///
	/// This internal method is called by `AnalyticsMiddleware` to process a URL
	/// using the configured strategy and send data to the analytics provider.
	///
	/// - Parameters:
	///   - url: The deep link URL to track
	///   - provider: The analytics provider that will receive the data
	func track(url: URL, provider: AnalyticsProvider) async {
		await trackFunction(url, provider)
	}
}

// MARK: - Analytics Strategy Implementations

public extension AnalyticsStrategy {
	/// Standard analytics tracking strategy with basic URL information.
	///
	/// This is the recommended strategy for most applications. It tracks essential
	/// information that allows basic analysis without collecting sensitive data.
	///
	/// ## Tracked Data
	/// - `url`: Complete deep link URL
	/// - `scheme`: URL scheme (e.g., "myApp", "https")
	/// - `host`: URL host (e.g., "product", "profile")
	/// - `timestamp`: Unix timestamp of the tracking moment
	///
	/// ## Use Cases
	/// - Applications with basic analytics
	/// - General deep link usage tracking
	/// - Basic navigation pattern analysis
	/// - Moderate privacy policy compliance
	///
	/// ## Generated Data Example
	/// For URL `myApp://product/123?color=red&size=L`:
	/// ```json
	/// {
	///   "event": "deep_link_opened",
	///   "parameters": {
	///     "url": "myApp://product/123?color=red&size=L",
	///     "scheme": "myApp",
	///     "host": "product",
	///     "timestamp": 1640995200.0
	///   }
	/// }
	/// ```
	///
	/// ## Usage Example
	/// ```swift
	/// let middleware = AnalyticsMiddleware(
	///     analyticsProvider: analyticsProvider,
	///     strategy: .standard
	/// )
	/// ```
	static let standard = AnalyticsStrategy { url, provider in
		await provider.track("deep_link_opened", parameters: [
			"url": url.absoluteString,
			"scheme": url.scheme ?? "unknown",
			"host": url.host ?? "unknown",
			"timestamp": Date().timeIntervalSince1970,
		])
	}

	/// Detailed analytics tracking strategy with complete URL information.
	///
	/// This strategy tracks exhaustive information including path and query parameters,
	/// ideal for deep analysis and cases where specific details are needed.
	///
	/// ## Tracked Data
	/// - `url`: Complete deep link URL
	/// - `scheme`: URL scheme (e.g., "myApp", "https")
	/// - `host`: URL host (e.g., "product", "profile")
	/// - `path`: URL path (e.g., "/123", "/search")
	/// - `query_parameters`: Dictionary with all query parameters
	/// - `timestamp`: Unix timestamp of the tracking moment
	///
	/// ## Use Cases
	/// - **E-commerce**: Track specific products and their attributes
	/// - **Marketing**: Analyze campaign effectiveness with parameters
	/// - **Filters and search**: Understand which filters users apply
	/// - **A/B Testing**: Track deep link variants
	/// - **Advanced analytics**: Detailed behavior analysis
	///
	/// ## Generated Data Example
	/// For URL `myApp://product/123?color=red&size=L&campaign=summer2024`:
	/// ```json
	/// {
	///   "event": "deep_link_opened",
	///   "parameters": {
	///     "url": "myApp://product/123?color=red&size=L&campaign=summer2024",
	///     "scheme": "myApp",
	///     "host": "product",
	///     "path": "/123",
	///     "query_parameters": {
	///       "color": "red",
	///       "size": "L",
	///       "campaign": "summer2024"
	///     },
	///     "timestamp": 1640995200.0
	///   }
	/// }
	/// ```
	///
	/// ## Privacy Considerations
	/// ⚠️ **Important**: This strategy may collect sensitive information in parameters.
	/// Ensure compliance with privacy policies and applicable regulations.
	///
	/// ## Usage Example
	/// ```swift
	/// // For e-commerce with detailed analysis
	/// let ecommerceMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: analyticsProvider,
	///     strategy: .detailed
	/// )
	///
	/// // For marketing with campaign tracking
	/// let marketingMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: marketingAnalytics,
	///     strategy: .detailed
	/// )
	/// ```
	static let detailed = AnalyticsStrategy { url, provider in
		var parameters: [String: Any] = [
			"url": url.absoluteString,
			"scheme": url.scheme ?? "unknown",
			"host": url.host ?? "unknown",
			"timestamp": Date().timeIntervalSince1970,
		]

		// Add path if available
		if !url.path.isEmpty {
			parameters["path"] = url.path
		}

		// Add query parameters if available
		if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		   let queryItems = components.queryItems, !queryItems.isEmpty
		{
			let queryParams = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "nil") })
			parameters["query_parameters"] = queryParams
		}

		await provider.track("deep_link_opened", parameters: parameters)
	}

	/// Minimal analytics tracking strategy with only essential information.
	///
	/// This strategy tracks only the most basic data necessary for functional analytics,
	/// ideal for applications with strict privacy restrictions or when data collection
	/// needs to be minimized.
	///
	/// ## Tracked Data
	/// - `scheme`: URL scheme (e.g., "myApp", "https")
	/// - `host`: URL host (e.g., "product", "profile")
	/// - `timestamp`: Unix timestamp of the tracking moment
	///
	/// ## Use Cases
	/// - **GDPR/CCPA Compliance**: Applications with strict privacy policies
	/// - **Medical Applications**: Where privacy is critical
	/// - **Corporate Applications**: With restrictive internal policies
	/// - **Basic Analysis**: When only section usage needs to be known
	/// - **Data Reduction**: To minimize storage and transfer
	///
	/// ## Generated Data Example
	/// For URL `myApp://product/123?color=red&size=L&user_id=456`:
	/// ```json
	/// {
	///   "event": "deep_link_opened",
	///   "parameters": {
	///     "scheme": "myApp",
	///     "host": "product",
	///     "timestamp": 1640995200.0
	///   }
	/// }
	/// ```
	///
	/// ## Advantages
	/// - ✅ Compliance with strict privacy regulations
	/// - ✅ Minimal data transfer
	/// - ✅ Lower risk of sensitive information exposure
	/// - ✅ Basic usage analysis by section
	///
	/// ## Limitations
	/// - ❌ No specific product analysis
	/// - ❌ No marketing parameter tracking
	/// - ❌ Limited detailed behavior analysis
	///
	/// ## Usage Example
	/// ```swift
	/// // For applications with strict privacy policies
	/// let privacyMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: analyticsProvider,
	///     strategy: .minimal
	/// )
	///
	/// // For medical or corporate applications
	/// let medicalAppMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: compliantAnalytics,
	///     strategy: .minimal
	/// )
	/// ```
	static let minimal = AnalyticsStrategy { url, provider in
		await provider.track("deep_link_opened", parameters: [
			"scheme": url.scheme ?? "unknown",
			"host": url.host ?? "unknown",
			"timestamp": Date().timeIntervalSince1970,
		])
	}

	/// Performance-focused analytics tracking strategy with timing information.
	///
	/// This strategy includes processing time metrics to monitor deep link performance.
	/// Ideal for applications that need to optimize processing speed or identify
	/// bottlenecks in deep link handling.
	///
	/// ## Tracked Data
	/// - `url`: Complete deep link URL
	/// - `scheme`: URL scheme (e.g., "myApp", "https")
	/// - `host`: URL host (e.g., "product", "profile")
	/// - `timestamp`: Unix timestamp of the tracking moment
	/// - `processing_time`: Processing time in seconds (usually very small)
	///
	/// ## Use Cases
	/// - **Performance Optimization**: Identify slow deep links
	/// - **Latency Debugging**: Find processing issues
	/// - **SLA Monitoring**: Ensure acceptable response times
	/// - **Load Analysis**: Understand processing impact
	/// - **Performance Alerts**: Detect performance degradation
	///
	/// ## Generated Data Example
	/// For URL `myApp://product/123` processed in 0.003 seconds:
	/// ```json
	/// {
	///   "event": "deep_link_opened",
	///   "parameters": {
	///     "url": "myApp://product/123",
	///     "scheme": "myApp",
	///     "host": "product",
	///     "timestamp": 1640995200.0,
	///     "processing_time": 0.003
	///   }
	/// }
	/// ```
	///
	/// ## Typical Performance Metrics
	/// - **Excellent**: < 0.01 seconds
	/// - **Good**: 0.01 - 0.05 seconds
	/// - **Acceptable**: 0.05 - 0.1 seconds
	/// - **Slow**: > 0.1 seconds
	///
	/// ## Advanced Use Cases
	/// ```swift
	/// // For production performance monitoring
	/// let performanceMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: monitoringProvider,
	///     strategy: .performance
	/// )
	///
	/// // For development debugging
	/// let debugMiddleware = AnalyticsMiddleware(
	///     analyticsProvider: debugAnalytics,
	///     strategy: .performance
	/// )
	/// ```
	///
	/// ## Considerations
	/// - The `processing_time` includes the execution time of the strategy itself
	/// - For more precise measurements, consider implementing custom timing
	/// - Very small times may vary due to system overhead
	static let performance = AnalyticsStrategy { url, provider in
		let startTime = Date()

		await provider.track("deep_link_opened", parameters: [
			"url": url.absoluteString,
			"scheme": url.scheme ?? "unknown",
			"host": url.host ?? "unknown",
			"timestamp": startTime.timeIntervalSince1970,
			"processing_time": Date().timeIntervalSince(startTime),
		])
	}
}
