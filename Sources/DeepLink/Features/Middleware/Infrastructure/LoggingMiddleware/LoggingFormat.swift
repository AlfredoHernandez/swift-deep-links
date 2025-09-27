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
