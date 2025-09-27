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
