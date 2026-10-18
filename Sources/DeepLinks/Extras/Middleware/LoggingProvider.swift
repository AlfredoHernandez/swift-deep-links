//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import os.log

/// A logging provider that uses the protocol witness pattern for flexible, type-safe logging.
///
/// `LoggingProvider` wraps a logging function, allowing different logging backends to be
/// plugged in without requiring a formal protocol. This design provides better performance
/// (no protocol dispatch overhead) and more flexibility than traditional protocol-based
/// logging systems.
///
/// ## Protocol Witness Pattern Benefits
///
/// - **No protocol overhead**: Direct function calls instead of virtual dispatch
/// - **Flexible**: Easy to adapt existing logging systems
/// - **Testable**: Simple to mock with custom logging functions
/// - **Composable**: Can wrap other logging providers
///
/// ## Built-in Implementations
///
/// - `systemLogger(_:)`: Use the system's `os.log.Logger`
/// - `defaultSystemLogger()`: Pre-configured system logger
/// - `console`: Print to console (for testing)
/// - `noOp`: Silent logging provider (for testing)
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
	/// Use this initializer to create a logging provider that logs to your own
	/// custom logging system. The provided closure is responsible for formatting,
	/// routing, and persisting the log message.
	///
	/// ## Thread Safety
	///
	/// The closure must be `Sendable` and thread-safe, as it may be called from
	/// different execution contexts.
	///
	/// ## Examples
	///
	/// ```swift
	/// // Log to custom backend
	/// let provider = LoggingProvider { level, message in
	///     MyAnalyticsService.log(level: level, message: message)
	/// }
	///
	/// // Log to file
	/// let provider = LoggingProvider { level, message in
	///     FileLogger.shared.write("\(level): \(message)")
	/// }
	/// ```
	///
	/// - Parameter logFunction: A closure that defines how to log messages.
	///                         The closure receives the log level and message.
	public init(_ logFunction: @escaping @Sendable (OSLogType, String) -> Void) {
		self.logFunction = logFunction
	}

	/// Logs a message with the specified level.
	///
	/// This method delegates to the underlying logging function, allowing the
	/// provider to handle the actual logging implementation.
	///
	/// - Parameters:
	///   - level: The log level for the message (`info`, `debug`, `error`, `fault`)
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

	/// A logging provider that prints to the console (useful for testing),
	/// redacting every URL embedded in a message.
	static var console: LoggingProvider {
		console(privacy: .redacted)
	}

	/// Creates a logging provider that prints to the console.
	///
	/// Printed output is visible in device logs and crash reporters, so URLs
	/// embedded in messages are redacted unless `privacy` is
	/// ``DeepLinkLogPrivacy/unredacted``.
	///
	/// - Parameter privacy: How URLs embedded in messages are printed.
	/// - Returns: A `LoggingProvider` that prints messages to the console
	static func console(privacy: DeepLinkLogPrivacy) -> LoggingProvider {
		console(privacy: privacy) { print($0) }
	}

	internal static func console(privacy: DeepLinkLogPrivacy, write: @escaping @Sendable (String) -> Void) -> LoggingProvider {
		LoggingProvider { level, message in
			write("[\(level.name)] \(privacy.redactingURLs(in: message))")
		}
	}

	/// Creates a logging provider that does nothing (useful for testing).
	///
	/// - Returns: A `LoggingProvider` that discards all log messages
	static var noOp: LoggingProvider {
		LoggingProvider { _, _ in }
	}
}

private extension OSLogType {
	/// Human-readable name for the log type, used by the console logging provider.
	var name: String {
		switch self {
		case .debug: "debug"
		case .info: "info"
		case .default: "default"
		case .error: "error"
		case .fault: "fault"
		default: "level(\(rawValue))"
		}
	}
}
