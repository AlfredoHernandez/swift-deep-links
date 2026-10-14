//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - **Flexible data collection**: Customizable parameter tracking
///
/// ## Available Strategies
/// - `.standard`: Basic information for general use
/// - `.detailed`: Complete information including parameters
/// - `.minimal`: Only essential data for restricted cases
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
/// ## Strategy Comparison
///
/// | Strategy | URL | Scheme | Host | Path | Parameters | Timestamp |
/// |----------|-----|--------|------|------|------------|-----------|
/// | `.minimal` | No | Yes | Yes | No | No | Yes |
/// | `.standard` | Yes | Yes | Yes | No | No | Yes |
/// | `.detailed` | Yes | Yes | Yes | Yes | Yes | Yes |
///
/// - SeeAlso: ``AnalyticsMiddleware`` to implement the middleware
/// - SeeAlso: ``AnalyticsProvider`` for custom providers
public struct AnalyticsStrategy: Sendable {
	private let trackFunction: @Sendable (URL, AnalyticsProvider) -> Void
	private let privacy: DeepLinkLogPrivacy

	init(privacy: DeepLinkLogPrivacy = .redacted, _ trackFunction: @escaping @Sendable (URL, AnalyticsProvider) -> Void) {
		self.trackFunction = trackFunction
		self.privacy = privacy
	}

	/// Executes the analytics tracking strategy.
	///
	/// This internal method is called by `AnalyticsMiddleware` to process a URL
	/// using the configured strategy and send data to the analytics provider.
	///
	/// - Parameters:
	///   - url: The deep link URL to track
	///   - provider: The analytics provider that will receive the data
	func track(url: URL, provider: AnalyticsProvider) {
		trackFunction(privacy.redact(url), provider)
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
		provider.track(
			"deep_link_opened",
			parameters: AnalyticsEventBuilder.parameters(for: url, detail: .withURL),
		)
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
	/// Important: This strategy may collect sensitive information in parameters.
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
		var parameters = AnalyticsEventBuilder.parameters(for: url, detail: .fullOmittingEmptyPath)

		if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		   let queryItems = components.queryItems, !queryItems.isEmpty
		{
			let queryParams = Dictionary(queryItems.map { ($0.name, $0.value ?? "nil") }, uniquingKeysWith: { _, last in last })
			parameters["query_parameters"] = queryParams
		}

		provider.track("deep_link_opened", parameters: parameters)
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
	/// - Compliance with strict privacy regulations
	/// - Minimal data transfer
	/// - Lower risk of sensitive information exposure
	/// - Basic usage analysis by section
	///
	/// ## Limitations
	/// - No specific product analysis
	/// - No marketing parameter tracking
	/// - Limited detailed behavior analysis
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
		provider.track(
			"deep_link_opened",
			parameters: AnalyticsEventBuilder.parameters(for: url, detail: .hostOnly),
		)
	}
}

// MARK: - Redaction

public extension AnalyticsStrategy {
	/// `strategy` tracking a copy of the URL redacted with `redactor`.
	///
	/// Built-in strategies already redact with the default redactor since 2.0;
	/// use this to supply custom sensitive keys. Sensitive query and fragment values and userinfo are replaced before
	/// `strategy` builds its event, so URLs and query parameters sent to
	/// third-party providers never carry tokens, codes or emails.
	///
	/// ```swift
	/// let middleware = AnalyticsMiddleware(
	///     analyticsProvider: provider,
	///     strategy: .redacted(.standard)
	/// )
	/// ```
	///
	/// - Parameters:
	///   - strategy: The strategy to apply to the redacted URL.
	///   - redactor: The redactor to use. Defaults to the default sensitive keys.
	/// - Returns: A strategy that never tracks the redacted values.
	static func redacted(_ strategy: AnalyticsStrategy, using redactor: URLRedactor = URLRedactor()) -> AnalyticsStrategy {
		AnalyticsStrategy(privacy: .redacted(using: redactor), strategy.trackFunction)
	}

	/// `strategy` tracking full, unredacted URLs.
	///
	/// Built-in strategies redact by default since 2.0. Use this only when the
	/// analytics backend is allowed to receive tokens, codes and e-mail
	/// addresses carried by deep links, for example while debugging.
	///
	/// ```swift
	/// .analytics(provider: provider, strategy: .unredacted(.standard))
	/// ```
	///
	/// - Parameter strategy: The strategy whose output to keep unredacted.
	/// - Returns: A strategy that tracks the original URL.
	static func unredacted(_ strategy: AnalyticsStrategy) -> AnalyticsStrategy {
		AnalyticsStrategy(privacy: .unredacted, strategy.trackFunction)
	}
}
