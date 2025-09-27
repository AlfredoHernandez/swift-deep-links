//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A delegate implementation that tracks deep link processing events for analytics.
///
/// This delegate automatically tracks deep link usage patterns, performance metrics,
/// and error rates to help understand how users interact with deep links in your app.
///
/// ## Usage
///
/// ```swift
/// let analyticsDelegate = DeepLinkAnalyticsDelegate(analyticsProvider: yourAnalyticsProvider)
/// coordinator.delegate = analyticsDelegate
/// ```
///
/// ## Tracked Events
///
/// - **deep_link_attempted**: When a deep link processing begins
/// - **deep_link_processed**: When deep link processing completes (success or failure)
/// - **deep_link_failed**: When deep link processing fails with an error
///
/// ## Analytics Parameters
///
/// Each event includes relevant parameters such as:
/// - URL scheme and host
/// - Processing time
/// - Success/failure status
/// - Number of routes processed
/// - Error details (if applicable)
public final class DeepLinkAnalyticsDelegate: DeepLinkCoordinatorDelegate, @unchecked Sendable {
    private let analyticsProvider: AnalyticsProvider

    /// Creates a new analytics delegate.
    ///
    /// - Parameter analyticsProvider: The analytics provider to use for tracking events
    public init(analyticsProvider: AnalyticsProvider) {
        self.analyticsProvider = analyticsProvider
    }

    public func coordinator(
        _: AnyObject,
        willProcess url: URL,
    ) {
        Task { [analyticsProvider] in
            await analyticsProvider.track("deep_link_attempted", parameters: [
                "url": url.absoluteString,
                "scheme": url.scheme ?? "unknown",
                "host": url.host() ?? "unknown",
                "path": url.path,
                "timestamp": Date().timeIntervalSince1970,
            ])
        }
    }

    public func coordinator(
        _: AnyObject,
        didProcess url: URL,
        result: DeepLinkResultProtocol,
    ) {
        Task { [analyticsProvider] in
            var parameters: [String: Any] = [
                "url": url.absoluteString,
                "scheme": url.scheme ?? "unknown",
                "host": url.host() ?? "unknown",
                "path": url.path,
                "success": result.wasSuccessful,
                "execution_time": result.executionTime,
                "successful_routes": result.successfulRoutes,
                "failed_routes": result.failedRoutes,
                "errors_count": result.errors.count,
                "was_stopped_by_middleware": result.wasStoppedByMiddleware,
                "timestamp": Date().timeIntervalSince1970,
            ]

            // Add error details if there are errors
            if !result.errors.isEmpty {
                parameters["error_descriptions"] = result.errors.map(\.localizedDescription)
            }

            await analyticsProvider.track("deep_link_processed", parameters: parameters)
        }
    }

    public func coordinator(
        _: AnyObject,
        didFailProcessing url: URL,
        error: Error,
    ) {
        Task { [analyticsProvider] in
            await analyticsProvider.track("deep_link_failed", parameters: [
                "url": url.absoluteString,
                "scheme": url.scheme ?? "unknown",
                "host": url.host() ?? "unknown",
                "path": url.path,
                "error_description": error.localizedDescription,
                "error_domain": (error as NSError).domain,
                "error_code": (error as NSError).code,
                "timestamp": Date().timeIntervalSince1970,
            ])
        }
    }
}
