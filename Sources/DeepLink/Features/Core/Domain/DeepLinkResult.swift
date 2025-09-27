//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Represents the result of processing a deep link URL through the coordinator.
///
/// This struct provides comprehensive information about the deep link processing,
/// including the processed URL, routes found, execution time, any errors that occurred,
/// and whether the processing was successful.
///
/// ## Usage
///
/// ```swift
/// let result = await coordinator.handle(url: deepLinkURL)
///
/// if result.wasSuccessful {
///     print("Processed \(result.routes.count) routes in \(result.executionTime)s")
/// } else {
///     print("Failed with errors: \(result.errors)")
/// }
/// ```
public struct DeepLinkResult<Route: DeepLinkRoute>: Sendable, DeepLinkResultProtocol {
    /// The original URL that was processed
    public let originalURL: URL

    /// The URL after middleware processing (nil if middleware stopped processing)
    public let processedURL: URL?

    /// The routes that were found and processed
    public let routes: [Route]

    /// The total execution time in seconds
    public let executionTime: TimeInterval

    /// Any errors that occurred during processing
    public let errors: [Error]

    /// Whether the processing was completely successful
    public let wasSuccessful: Bool

    /// The number of routes that were successfully processed
    public let successfulRoutes: Int

    /// The number of routes that failed during processing
    public let failedRoutes: Int

    /// Creates a new deep link result.
    ///
    /// - Parameters:
    ///   - originalURL: The original URL that was processed
    ///   - processedURL: The URL after middleware processing
    ///   - routes: The routes that were found
    ///   - executionTime: The total execution time
    ///   - errors: Any errors that occurred
    ///   - successfulRoutes: Number of successfully processed routes
    ///   - failedRoutes: Number of failed routes
    public init(
        originalURL: URL,
        processedURL: URL?,
        routes: [Route],
        executionTime: TimeInterval,
        errors: [Error] = [],
        successfulRoutes: Int = 0,
        failedRoutes: Int = 0,
    ) {
        self.originalURL = originalURL
        self.processedURL = processedURL
        self.routes = routes
        self.executionTime = executionTime
        self.errors = errors
        self.successfulRoutes = successfulRoutes
        self.failedRoutes = failedRoutes
        wasSuccessful = errors.isEmpty && failedRoutes == 0
    }
}

// MARK: - Convenience Properties

public extension DeepLinkResult {
    /// Whether middleware stopped the processing
    var wasStoppedByMiddleware: Bool {
        processedURL == nil
    }

    /// Whether any routes were found
    var hasRoutes: Bool {
        !routes.isEmpty
    }

    /// Whether any errors occurred
    var hasErrors: Bool {
        !errors.isEmpty
    }

    /// The first error that occurred (if any)
    var firstError: Error? {
        errors.first
    }

    /// A human-readable summary of the result
    var summary: String {
        if wasStoppedByMiddleware {
            "Processing stopped by middleware"
        } else if wasSuccessful {
            "Successfully processed \(successfulRoutes) route(s) in \(String(format: "%.3f", executionTime))s"
        } else {
            "Processed \(successfulRoutes)/\(routes.count) routes with \(errors.count) error(s) in \(String(format: "%.3f", executionTime))s"
        }
    }
}
