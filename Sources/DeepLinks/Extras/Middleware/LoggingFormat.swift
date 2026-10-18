//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import os.log

/// A logging format provider that uses the protocol witness pattern for flexible, composable logging strategies.
///
/// `LoggingFormat` encapsulates different ways to format and output deep link logging information.
/// It uses the protocol witness pattern to provide type-safe, composable strategies without
/// the overhead of protocols. This allows for efficient, stateless logging implementations
/// that can be easily tested, extended, and composed.
///
/// ## Protocol Witness Pattern Benefits
///
/// - **Performance**: No protocol dispatch overhead compared to protocol-based logging
/// - **Type Safety**: Compile-time guarantees about logging behavior
/// - **Composability**: Easy to create new formats by combining existing ones
/// - **Testability**: Simple to mock and test individual format strategies
/// - **Flexibility**: Can adapt to any logging backend
///
/// ## Built-in Strategies
///
/// - `.singleLine`: Compact single-line format with all components
/// - `.json`: Structured JSON format for log aggregation systems
/// - `.minimal`: URL-only format for lightweight logging
/// - `.detailed`: Multi-line detailed format for debugging
///
/// ## Usage Examples
///
/// ### Using Built-in Formats
///
/// ```swift
/// // Development debugging with detailed format
/// let middleware = LoggingMiddleware(format: .detailed)
///
/// // Production with minimal logging
/// let middleware = LoggingMiddleware(format: .minimal)
///
/// // Analytics integration with JSON format
/// let middleware = LoggingMiddleware(format: .json)
/// ```
///
/// ### Creating Custom Formats
///
/// ```swift
/// // Create a custom logging format
/// let customFormat = LoggingFormat { url, components, logger, logLevel in
///     let customMessage = "APP: \(components.host ?? "?") => \(url.path)"
///     logger.log(level: logLevel, customMessage)
/// }
///
/// // Use with LoggingMiddleware
/// let middleware = LoggingMiddleware(format: customFormat)
/// ```
public struct LoggingFormat: Sendable {
	private let logFunction: @Sendable (URL, DeepLinkComponents, LoggingProvider, OSLogType) -> Void
	private let privacy: DeepLinkLogPrivacy

	/// Creates a new logging format with a custom logging function.
	///
	/// Use this initializer to implement custom logging formats that match your
	/// specific requirements. The provided closure receives all necessary information
	/// about the deep link and can format and log it however needed.
	///
	/// ## Parameters
	///
	/// - **url**: The original deep link URL being processed
	/// - **components**: Pre-parsed URL components for convenient access
	/// - **loggingProvider**: The logging provider to use for output
	/// - **logLevel**: The OSLogType level for the message
	///
	/// ## Thread Safety
	///
	/// The closure must be `Sendable` and thread-safe, as it may be called from
	/// different execution contexts.
	///
	/// - Parameter logFunction: A closure that defines how to format and log
	///                         deep link information.
	init(privacy: DeepLinkLogPrivacy = .redacted, _ logFunction: @escaping @Sendable (URL, DeepLinkComponents, LoggingProvider, OSLogType) -> Void) {
		self.logFunction = logFunction
		self.privacy = privacy
	}

	/// Executes the logging strategy with the provided parameters.
	///
	/// This method delegates to the configured logging function, allowing
	/// different format strategies to be applied consistently.
	///
	/// - Parameters:
	///   - url: The deep link URL to log
	///   - components: Parsed URL components for detailed logging
	///   - loggingProvider: The logging provider to use for output
	///   - logLevel: The log level for the message
	func log(url: URL, components: DeepLinkComponents, loggingProvider: LoggingProvider, logLevel: OSLogType) {
		let loggedURL = privacy.redact(url)
		let loggedComponents = loggedURL == url ? components : DeepLinkComponents(from: loggedURL)
		logFunction(loggedURL, loggedComponents, loggingProvider, logLevel)
	}
}

// MARK: - Logging Format Strategies

/// Logging format strategies for deep links.
///
/// These strategies provide various ways to format deep link logging output,
/// each optimized for specific scenarios like development, production, or
/// integration with log aggregation systems.
///
/// ## Features
/// - **Multiple formats**: From minimal to detailed logging
/// - **Environment optimization**: Formats for different environments
/// - **Structured logging**: JSON format for log aggregation systems
/// - **Performance aware**: Minimal overhead options
///
/// ## Available Strategies
/// - `.singleLine`: Compact format with all details on one line
/// - `.json`: Structured JSON format for log aggregation systems
/// - `.minimal`: Only logs the URL for lightweight logging
/// - `.detailed`: Multi-line format with separate entries for each component
///
/// ## Usage Examples
///
/// ### Development Format
/// ```swift
/// let middleware = LoggingMiddleware(format: .detailed)
/// ```
///
/// ### Production Format
/// ```swift
/// let middleware = LoggingMiddleware(format: .singleLine)
/// ```
///
/// ### Analytics Integration
/// ```swift
/// let middleware = LoggingMiddleware(format: .json)
/// ```
///
/// ### High Performance
/// ```swift
/// let middleware = LoggingMiddleware(format: .minimal)
/// ```
///
/// ## Strategy Comparison
///
/// | Strategy | Format | Details | Performance | Use Case |
/// |----------|--------|---------|-------------|----------|
/// | `.minimal` | Single line | URL only | Highest | Production monitoring |
/// | `.singleLine` | Single line | All components | High | General purpose |
/// | `.detailed` | Multi-line | All components | Medium | Development |
/// | `.json` | JSON | All components | Medium | Analytics/ELK |
public extension LoggingFormat {
	/// Single line format with all details separated by pipes and commas.
	///
	/// This is the default format that provides a good balance between readability
	/// and information density. It's ideal for development and production monitoring
	/// where you need detailed information in a compact format.
	///
	/// ## Example Output
	/// ```
	/// Deep link intercepted: myapp://product/123 | scheme=myapp, host=product, path=/123, params=id=123&color=red
	/// ```
	///
	/// ## When to Use
	/// - Development debugging
	/// - Production monitoring
	/// - Console logging where space is limited
	/// - General-purpose logging that needs to be human-readable
	static let singleLine = LoggingFormat { url, components, loggingProvider, logLevel in
		let details = buildComponentDetails(components)
		let message = details.isEmpty
			? "Deep link intercepted: \(url.absoluteString)"
			: "Deep link intercepted: \(url.absoluteString) | \(details.joined(separator: ", "))"

		loggingProvider.log(level: logLevel, message)
	}

	/// JSON format for structured logging and log aggregation systems.
	///
	/// This format outputs structured JSON that can be easily parsed by log
	/// aggregation systems like ELK Stack, Splunk, or cloud logging services.
	/// It provides machine-readable format with all deep link components.
	///
	/// ## Example Output
	/// ```json
	/// {
	///   "event": "deep_link_intercepted",
	///   "url": "myapp://product/123",
	///   "scheme": "myapp",
	///   "host": "product",
	///   "path": "/123",
	///   "params": {
	///     "id": "123",
	///     "color": "red"
	///   }
	/// }
	/// ```
	///
	/// ## When to Use
	/// - Integration with log aggregation systems (ELK, Splunk, etc.)
	/// - Cloud logging services (AWS CloudWatch, Google Cloud Logging)
	/// - Analytics and monitoring dashboards
	/// - Automated log processing and alerting
	/// - Production environments with structured logging requirements
	static let json = LoggingFormat { url, components, loggingProvider, logLevel in
		var logData: [String: Any] = [
			"event": "deep_link_intercepted",
			"url": url.absoluteString,
		]

		if let scheme = components.scheme {
			logData["scheme"] = scheme
		}

		if let host = components.host {
			logData["host"] = host
		}

		if !components.path.isEmpty {
			logData["path"] = components.path
		}

		if components.hasQueryItems {
			logData["params"] = components.queryParametersDictionary
		}

		do {
			let jsonData = try JSONSerialization.data(withJSONObject: logData, options: [])
			if let jsonString = String(data: jsonData, encoding: .utf8) {
				loggingProvider.log(level: logLevel, jsonString)
			}
		} catch {
			loggingProvider.log(level: logLevel, "Deep link intercepted: \(url.absoluteString) (JSON serialization failed)")
		}
	}

	/// Minimal format showing only the URL.
	///
	/// This format provides the most lightweight logging possible, showing only
	/// the deep link URL without any additional parsing or component details.
	/// It's ideal for high-volume logging scenarios where you need to minimize
	/// log size and processing overhead.
	///
	/// ## Example Output
	/// ```
	/// Deep link: myapp://product/123?id=123&color=red
	/// ```
	///
	/// ## When to Use
	/// - High-volume production logging
	/// - Performance-critical applications
	/// - Logging systems with storage constraints
	/// - Simple monitoring that only needs URL tracking
	/// - Debug builds where you want minimal console output
	static let minimal = LoggingFormat { url, _, loggingProvider, logLevel in
		loggingProvider.log(level: logLevel, "Deep link: \(url.absoluteString)")
	}

	/// Detailed format with each component on a separate line.
	///
	/// This format provides the most comprehensive logging output, with each
	/// URL component logged on its own line. It's perfect for detailed debugging
	/// and development scenarios where you need to see all available information
	/// about a deep link in a clear, structured way.
	///
	/// ## Example Output
	/// ```
	/// Deep link intercepted: myapp://product/123?id=123&color=red
	/// Scheme: myapp
	/// Host: product
	/// Path: /123
	/// Parameters: id=123&color=red
	/// ```
	///
	/// ## When to Use
	/// - Development and debugging
	/// - Troubleshooting deep link issues
	/// - Detailed analysis of URL structure
	/// - Testing and validation scenarios
	/// - Development environments where verbose output is acceptable
	static let detailed = LoggingFormat { url, components, loggingProvider, logLevel in
		loggingProvider.log(level: logLevel, "Deep link intercepted: \(url.absoluteString)")
		loggingProvider.log(level: logLevel, "Scheme: \(components.scheme ?? "nil")")
		loggingProvider.log(level: logLevel, "Host: \(components.host ?? "nil")")
		loggingProvider.log(level: logLevel, "Path: \(components.path)")

		if components.hasQueryItems {
			loggingProvider.log(level: logLevel, "Parameters: \(components.queryParametersString)")
		}
	}
}

// MARK: - Redaction

public extension LoggingFormat {
	/// `format` logging a copy of the URL and its components redacted with `redactor`.
	///
	/// Built-in formats already redact with the default redactor since 2.0;
	/// use this to supply custom sensitive keys. Sensitive query and fragment values and userinfo are replaced before
	/// `format` sees the URL, so every built-in or custom format can be made
	/// safe for production logs. The middleware still passes the original
	/// URL down the chain.
	///
	/// ```swift
	/// let middleware = LoggingMiddleware(format: .redacted(.json))
	/// // {"url":"myapp://reset?token=REDACTED", ...}
	/// ```
	///
	/// - Parameters:
	///   - format: The format to apply to the redacted URL.
	///   - redactor: The redactor to use. Defaults to ``URLRedactor/init(sensitiveKeys:placeholder:)``
	///     with the default sensitive keys.
	/// - Returns: A format that never logs the redacted values.
	static func redacted(_ format: LoggingFormat, using redactor: URLRedactor = URLRedactor()) -> LoggingFormat {
		LoggingFormat(privacy: .redacted(using: redactor), format.logFunction)
	}

	/// `format` logging full, unredacted URLs.
	///
	/// Built-in formats redact by default since 2.0. Use this only while
	/// debugging: deep links can carry tokens, codes and e-mail addresses.
	///
	/// ```swift
	/// .logging(format: .unredacted(.detailed))
	/// ```
	///
	/// - Parameter format: The format whose output to keep unredacted.
	/// - Returns: A format that logs the original URL.
	static func unredacted(_ format: LoggingFormat) -> LoggingFormat {
		LoggingFormat(privacy: .unredacted, format.logFunction)
	}
}

/// Builds a detailed string representation of deep link components.
///
/// This helper function creates an array of strings describing each component
/// of a deep link URL, used primarily by the `.singleLine` format strategy for compact logging.
///
/// The function builds an array of formatted component descriptions that can be joined
/// with separators to create readable single-line logging output. Only non-empty components
/// are included in the result.
///
/// ## Generated Format
///
/// For a URL like `myapp://product/123?id=123&color=red`, this function generates:
/// ```
/// ["scheme=myapp", "host=product", "path=/123", "params=id=123&color=red"]
/// ```
///
/// Which can be joined as:
/// ```
/// "scheme=myapp, host=product, path=/123, params=id=123&color=red"
/// ```
///
/// - Parameter components: The parsed deep link components to describe
/// - Returns: An array of strings describing each component (scheme, host, path, params).
///   Empty if the URL has no components or only a path.
/// - Complexity: O(n) where n is the number of components (typically constant since URLs have at most 4 main parts)
private func buildComponentDetails(_ components: DeepLinkComponents) -> [String] {
	var details: [String] = []

	if let scheme = components.scheme {
		details.append("scheme=\(scheme)")
	}

	if let host = components.host {
		details.append("host=\(host)")
	}

	if !components.path.isEmpty {
		details.append("path=\(components.path)")
	}

	if components.hasQueryItems {
		details.append("params=\(components.queryParametersString)")
	}

	return details
}
