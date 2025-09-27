//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for intercepting and processing deep links before they reach parsers.
///
/// Middleware allows you to intercept deep link URLs and perform operations such as:
/// - Analytics tracking
/// - Authentication validation
/// - Rate limiting
/// - Logging
/// - URL transformation
/// - Security validation
///
/// Middleware is executed in the order it's added to the coordinator, and each middleware
/// can either allow the URL to continue to the next middleware/parser, or stop the processing
/// by throwing an error or returning a modified URL.
///
/// ## Usage Example
///
/// ```swift
/// final class AnalyticsMiddleware: DeepLinkMiddleware {
///     func intercept(_ url: URL) async throws -> URL? {
///         // Track the deep link attempt
///         Analytics.track("deep_link_opened", parameters: [
///             "url": url.absoluteString,
///             "timestamp": Date().timeIntervalSince1970
///         ])
///
///         // Allow the URL to continue processing
///         return url
///     }
/// }
/// ```
public protocol DeepLinkMiddleware: Sendable {
    /// Intercepts a deep link URL before it reaches the parsers.
    ///
    /// - Parameter url: The deep link URL to intercept
    /// - Returns: The URL to continue processing with, or `nil` to stop processing
    /// - Throws: An error to stop processing and report the issue
    func intercept(_ url: URL) async throws -> URL?
}

/// Result of middleware processing
public enum MiddlewareResult {
    /// Continue processing with the original URL
    case `continue`(URL)

    /// Continue processing with a modified URL
    case transform(URL)

    /// Stop processing and report an error
    case error(Error)

    /// Stop processing without error (e.g., handled by middleware)
    case handled
}

/// Enhanced middleware protocol with more control over processing flow
public protocol AdvancedDeepLinkMiddleware: Sendable {
    /// Intercepts a deep link URL with full control over the processing flow.
    ///
    /// - Parameter url: The deep link URL to intercept
    /// - Returns: A result indicating how to proceed with processing
    func intercept(_ url: URL) async -> MiddlewareResult
}

/// Default implementation that converts AdvancedDeepLinkMiddleware to DeepLinkMiddleware
public extension AdvancedDeepLinkMiddleware {
    func intercept(_ url: URL) async throws -> URL? {
        let result = await intercept(url)

        switch result {
        case let .continue(url):
            return url

        case let .transform(url):
            return url

        case let .error(error):
            throw error

        case .handled:
            return nil
        }
    }
}
