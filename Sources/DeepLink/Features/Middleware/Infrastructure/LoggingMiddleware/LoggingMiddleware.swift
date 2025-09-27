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
