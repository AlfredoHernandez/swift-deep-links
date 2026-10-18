//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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
public struct DeepLinkResult<Route: DeepLinkRoute>: Sendable {
	/// The original URL that was processed
	public let originalURL: URL

	/// The URL after middleware processing (nil if middleware stopped processing)
	public let processedURL: URL?

	/// The routes that were found and processed
	public let routes: [Route]

	/// The total execution time in seconds
	public let executionTime: TimeInterval

	/// Any errors that occurred during processing
	public let errors: [any Error]

	/// Whether the processing was completely successful
	public let wasSuccessful: Bool

	/// The number of routes that were successfully processed
	public let successfulRoutes: Int

	/// The number of routes that failed during processing
	public let failedRoutes: Int

	/// Creates a new deep link processing result.
	///
	/// This initializer constructs a result object that captures all aspects of deep link
	/// processing, from the original URL through middleware processing, routing, and
	/// handler execution.
	///
	/// The `wasSuccessful` property is automatically computed as:
	/// - `processedURL != nil` (middleware didn't stop processing)
	/// - AND `errors.isEmpty` (no errors occurred)
	/// - AND `failedRoutes == 0` (all routes executed successfully)
	///
	/// - Parameters:
	///   - originalURL: The original URL that was submitted for processing. This is always
	///     captured regardless of processing outcome.
	///   - processedURL: The URL after all middleware processing. Set to `nil` if middleware
	///     stopped the processing chain.
	///   - routes: An array of routes found by the routing system. Empty if routing failed
	///     or middleware stopped processing.
	///   - executionTime: The total time taken for processing in seconds, measured from
	///     the start of middleware processing to the completion of all route handlers.
	///   - errors: An array of any errors that occurred during processing. Defaults to empty.
	///     May contain middleware errors, routing errors, or handler execution errors.
	///   - successfulRoutes: The count of routes that were successfully executed. Defaults to 0.
	///   - failedRoutes: The count of routes that failed during execution. Defaults to 0.
	///
	/// ## Computing Success
	///
	/// A result is considered successful when all three conditions are met:
	/// 1. Middleware allowed the URL to proceed (`processedURL != nil`)
	/// 2. No errors occurred during processing (`errors.isEmpty`)
	/// 3. All routes executed successfully (`failedRoutes == 0`)
	public init(
		originalURL: URL,
		processedURL: URL?,
		routes: [Route],
		executionTime: TimeInterval,
		errors: [any Error] = [],
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
		wasSuccessful = processedURL != nil && errors.isEmpty && failedRoutes == 0
	}
}

// MARK: - Convenience Properties

public extension DeepLinkResult {
	/// Whether middleware stopped the processing before routing.
	///
	/// Returns `true` if a middleware in the chain returned `nil` or stopped processing,
	/// preventing the URL from reaching the routing system.
	///
	/// When this is `true`, `processedURL` will be `nil` and no routes will be found.
	var wasStoppedByMiddleware: Bool {
		processedURL == nil
	}

	/// Whether any routes were found during routing.
	///
	/// Returns `true` if the routing system successfully found at least one route
	/// for the processed URL.
	var hasRoutes: Bool {
		!routes.isEmpty
	}

	/// Whether any errors occurred during processing or route execution.
	///
	/// Returns `true` if any errors were encountered during middleware processing,
	/// routing, or route handler execution.
	var hasErrors: Bool {
		!errors.isEmpty
	}

	/// The first error that occurred during processing, if any.
	///
	/// Returns the first error encountered, or `nil` if processing completed without errors.
	/// Useful for quick error handling when you only need to know about the first failure.
	var firstError: (any Error)? {
		errors.first
	}

	/// The first ``DeepLinkError`` in the error chain, if any.
	///
	/// Scans ``errors`` in order and returns the first entry that is a ``DeepLinkError``,
	/// ignoring other error types. Useful when you want to branch on the framework's
	/// typed error cases without losing non-framework errors from ``errors``.
	///
	/// ## Example
	///
	/// ```swift
	/// let result = await coordinator.handle(url: deepLinkURL)
	/// if let deepLinkError = result.firstDeepLinkError {
	///     switch deepLinkError {
	///     case .routeNotFound: showNotFoundAlert()
	///     default: showGenericAlert()
	///     }
	/// }
	/// ```
	var firstDeepLinkError: DeepLinkError? {
		errors.lazy.compactMap { $0 as? DeepLinkError }.first
	}

	/// A human-readable summary of the deep link processing result.
	///
	/// Provides a concise description of what happened during processing, including:
	/// - Whether middleware stopped processing
	/// - Number of successful and failed routes
	/// - Total execution time
	/// - Error count (if any)
	///
	/// ## Examples
	///
	/// ```swift
	/// let result = await coordinator.handle(url: deepLinkURL)
	///
	/// // Possible summaries:
	/// // "Processing stopped by middleware"
	/// // "Successfully processed 2 route(s) in 0.043s"
	/// // "Processed 1/2 routes with 1 error(s) in 0.156s"
	/// ```
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
