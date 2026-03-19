//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Represents the parsed components of a deep link URL for logging purposes.
///
/// `DeepLinkComponents` provides a structured way to access and format the
/// different parts of a deep link URL. It's designed specifically for logging
/// middleware to extract and display URL information in various formats.
///
/// ## Usage Example
///
/// ```swift
/// let url = URL(string: "myapp://product/123?id=123&color=red")!
/// let components = DeepLinkComponents(from: url)
///
/// print(components.scheme) // "myapp"
/// print(components.host)   // "product"
/// print(components.path)   // "/123"
/// print(components.queryParametersString) // "id=123&color=red"
/// ```
///
/// ## URL Structure
///
/// For a URL like `myapp://product/123?id=123&color=red`:
/// - **Scheme**: `myapp` (the app identifier)
/// - **Host**: `product` (the route or feature)
/// - **Path**: `/123` (the resource identifier)
/// - **Query Items**: `id=123&color=red` (additional parameters)
struct DeepLinkComponents {
	/// The URL scheme (e.g., "myapp" from "myapp://product/123")
	let scheme: String?

	/// The URL host (e.g., "product" from "myapp://product/123")
	let host: String?

	/// The URL path (e.g., "/123" from "myapp://product/123")
	let path: String

	/// The URL query items as an array of URLQueryItem objects
	let queryItems: [URLQueryItem]?

	/// Creates a new `DeepLinkComponents` instance by parsing the given URL.
	///
	/// - Parameter url: The deep link URL to parse
	init(from url: URL) {
		let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		scheme = components?.scheme
		host = components?.host
		path = components?.path ?? ""
		queryItems = components?.queryItems
	}

	/// Indicates whether the URL contains query parameters.
	///
	/// - Returns: `true` if the URL has query parameters, `false` otherwise
	var hasQueryItems: Bool {
		guard let queryItems else { return false }
		return !queryItems.isEmpty
	}

	/// Returns query parameters as a formatted string.
	///
	/// Converts query items to a URL-encoded string format suitable for logging.
	/// For example: "id=123&color=red&size=large"
	///
	/// - Returns: A string representation of query parameters, or empty string if none exist
	var queryParametersString: String {
		guard let queryItems, !queryItems.isEmpty else { return "" }
		return queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: "&")
	}

	/// Returns query parameters as a dictionary.
	///
	/// Converts query items to a dictionary format suitable for JSON logging
	/// and structured data processing.
	///
	/// - Returns: A dictionary with parameter names as keys and values as strings
	var queryParametersDictionary: [String: String] {
		guard let queryItems else { return [:] }
		return Dictionary(queryItems.map { ($0.name, $0.value ?? "nil") }, uniquingKeysWith: { _, last in last })
	}
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os.log

/// Protocol witness for logging functionality.
///
/// `LoggingProvider` uses the protocol witness pattern to provide a testable,
/// mockable interface for logging operations. This allows for better testability
/// and flexibility in logging implementations.
///
/// ## Benefits
///
/// - **Testability**: Easy to mock and verify logging calls in tests
/// - **Flexibility**: Can be replaced with different logging implementations
/// - **Performance**: No protocol dispatch overhead
/// - **Type Safety**: Compile-time guarantees about logging behavior
///
/// ## Usage Example
///
/// ```swift
/// // Create a custom logging provider
/// let customProvider = LoggingProvider { level, message in
///     print("[\(level)] \(message)")
/// }
///
/// // Use with LoggingMiddleware
/// let middleware = LoggingMiddleware(loggingProvider: customProvider)
/// ```
public struct LoggingProvider: Sendable {
	private let logFunction: @Sendable (OSLogType, String) -> Void

	/// Creates a new logging provider with a custom logging function.
	///
	/// - Parameter logFunction: A closure that defines how to log messages.
	///                         The closure receives the log level and message.
	public init(_ logFunction: @escaping @Sendable (OSLogType, String) -> Void) {
		self.logFunction = logFunction
	}

	/// Logs a message with the specified level.
	///
	/// - Parameters:
	///   - level: The log level for the message
	///   - message: The message to log
	public func log(level: OSLogType, _ message: String) {
		logFunction(level, message)
	}
}

// MARK: - Default Logging Providers

public extension LoggingProvider {
	/// Creates a logging provider that uses the system's `os.log.Logger`.
	///
	/// - Parameters:
	///   - logger: The `Logger` instance to use for output
	/// - Returns: A `LoggingProvider` that delegates to the system logger
	static func systemLogger(_ logger: Logger) -> LoggingProvider {
		LoggingProvider { level, message in
			logger.log(level: level, "\(message)")
		}
	}

	/// Creates a logging provider that uses a default system logger.
	///
	/// - Parameters:
	///   - subsystem: The subsystem identifier
	///   - category: The category identifier
	/// - Returns: A `LoggingProvider` with a default system logger
	static func defaultSystemLogger(
		subsystem: String = "swift-deep-link",
		category: String = "system-logger",
	) -> LoggingProvider {
		let logger = Logger(subsystem: subsystem, category: category)
		return .systemLogger(logger)
	}

	/// Creates a logging provider that prints to console (useful for testing).
	///
	/// - Returns: A `LoggingProvider` that prints messages to console
	static var console: LoggingProvider {
		LoggingProvider { level, message in
			print("[\(level.rawValue)] \(message)")
		}
	}

	/// Creates a logging provider that does nothing (useful for testing).
	///
	/// - Returns: A `LoggingProvider` that discards all log messages
	static var noOp: LoggingProvider {
		LoggingProvider { _, _ in }
	}
}

/// Protocol witness for logging format strategies.
///
/// `LoggingFormat` uses the protocol witness pattern to provide type-safe,
/// composable logging strategies without the overhead of protocols. This approach
/// allows for efficient, stateless logging format implementations that can be
/// easily tested and extended.
///
/// ## Protocol Witness Pattern Benefits
///
/// - **Performance**: No protocol dispatch overhead
/// - **Type Safety**: Compile-time guarantees about logging behavior
/// - **Composability**: Easy to create new formats by combining existing ones
/// - **Testability**: Simple to mock and test individual format strategies
///
/// ## Usage Example
///
/// ```swift
/// // Create a custom logging format
/// let customFormat = LoggingFormat { url, components, logger, logLevel in
///     logger.log(level: logLevel, "Custom: \(url.absoluteString)")
/// }
///
/// // Use with LoggingMiddleware
/// let middleware = LoggingMiddleware(format: customFormat)
/// ```
///
/// ## Available Strategies
///
/// - `.singleLine`: Compact single-line format
/// - `.json`: Structured JSON format
/// - `.minimal`: URL-only format
/// - `.detailed`: Multi-line detailed format
public struct LoggingFormat: Sendable {
	private let logFunction: @Sendable (URL, DeepLinkComponents, LoggingProvider, OSLogType) -> Void

	/// Creates a new logging format with a custom logging function.
	///
	/// - Parameter logFunction: A closure that defines how to format and log
	///                         deep link information. The closure receives the URL,
	///                         parsed components, logging provider, and log level.
	init(_ logFunction: @escaping @Sendable (URL, DeepLinkComponents, LoggingProvider, OSLogType) -> Void) {
		self.logFunction = logFunction
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
		logFunction(url, components, loggingProvider, logLevel)
	}
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os.log

/// Middleware for logging deep link attempts with configurable formats and log levels.
///
/// The `LoggingMiddleware` intercepts all deep link attempts and logs them using
/// the configured format strategy. This is useful for debugging, monitoring, and
/// analytics purposes.
///
/// ## Features
/// - **Configurable formats**: Multiple logging format strategies
/// - **Flexible providers**: Compatible with any logging system
/// - **Log level control**: Configurable log levels for different environments
/// - **Non-blocking flow**: The middleware doesn't interrupt normal deep link processing
///
/// ## Use Cases
/// - Debug deep link handling during development
/// - Monitor deep link usage in production
/// - Integrate with log aggregation systems
/// - Track deep link performance and errors
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let loggingMiddleware = LoggingMiddleware()
/// coordinator.addMiddleware(loggingMiddleware)
/// ```
///
/// ### Custom Logging Provider and Log Level
/// ```swift
/// let customProvider = LoggingProvider.systemLogger(
///     Logger(subsystem: "MyApp", category: "DeepLinks")
/// )
/// let loggingMiddleware = LoggingMiddleware(
///     loggingProvider: customProvider,
///     logLevel: .debug
/// )
/// ```
///
/// ### Different Log Formats
/// ```swift
/// // JSON format for structured logging
/// let jsonLogging = LoggingMiddleware(format: .json)
///
/// // Minimal format for production
/// let minimalLogging = LoggingMiddleware(format: .minimal)
///
/// // Detailed format for debugging
/// let detailedLogging = LoggingMiddleware(format: .detailed)
/// ```
///
/// ## Available Formats
/// - `.singleLine` (default): Compact format with all details on one line
/// - `.json`: Structured JSON format for log aggregation systems
/// - `.minimal`: Only logs the URL for lightweight logging
/// - `.detailed`: Multi-line format with separate entries for each component
///
/// ## Environment Recommendations
/// - **Development**: Use `.detailed` format with `.debug` level for comprehensive debugging
/// - **Production**: Use `.minimal` or `.singleLine` format with `.info` level for monitoring
/// - **Analytics**: Use `.json` format for integration with log aggregation systems
/// - **Testing**: Use custom logging provider with `.debug` level to verify deep link handling
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
public final class LoggingMiddleware: DeepLinkMiddleware {
	private let loggingProvider: LoggingProvider
	private let logLevel: OSLogType
	private let format: LoggingFormat

	/// Creates a new logging middleware with configurable logging behavior.
	///
	/// - Parameters:
	///   - loggingProvider: The `LoggingProvider` instance to use for output.
	///                      Defaults to a system logger with subsystem "DeepLink"
	///                      and category "Middleware".
	///   - logLevel: The `OSLogType` level for logging. Defaults to `.info`.
	///               Use `.debug` for development, `.info` for production monitoring.
	///   - format: The `LoggingFormat` strategy to use. Defaults to `.singleLine`.
	///             Choose based on your logging infrastructure needs.
	public init(
		loggingProvider: LoggingProvider = .defaultSystemLogger(),
		logLevel: OSLogType = .info,
		format: LoggingFormat = .singleLine,
	) {
		self.loggingProvider = loggingProvider
		self.logLevel = logLevel
		self.format = format
	}

	/// Intercepts a deep link URL and logs it using the configured format strategy.
	///
	/// This method parses the URL into components and logs them according to the
	/// configured `LoggingFormat` strategy. The original URL is always returned
	/// unchanged, allowing the middleware chain to continue processing.
	///
	/// - Parameter url: The deep link URL to log
	/// - Returns: The original URL unchanged, allowing middleware chain continuation
	/// - Throws: Never throws - logging failures are handled gracefully
	public func intercept(_ url: URL) async throws -> URL? {
		let components = DeepLinkComponents(from: url)
		format.log(url: url, components: components, loggingProvider: loggingProvider, logLevel: logLevel)
		return url
	}
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os.log

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

// MARK: - Helper Functions

/// Builds a detailed string representation of deep link components.
///
/// This helper function creates an array of strings describing each component
/// of a deep link URL, used primarily by the `.singleLine` format strategy.
///
/// - Parameter components: The parsed deep link components
/// - Returns: An array of strings describing each component (scheme, host, path, params)
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
