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
