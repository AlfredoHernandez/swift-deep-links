//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A protocol that represents the essential properties of a deep link result.
///
/// This protocol allows delegates to work with any deep link result type
/// without being tied to a specific route type.
public protocol DeepLinkResultProtocol: Sendable {
	/// The original URL that was processed
	var originalURL: URL { get }

	/// The URL after middleware processing, or nil if stopped
	var processedURL: URL? { get }

	/// The total execution time in seconds
	var executionTime: TimeInterval { get }

	/// A list of all errors encountered during processing
	var errors: [Error] { get }

	/// The number of routes that were successfully handled
	var successfulRoutes: Int { get }

	/// The number of routes that failed to be handled
	var failedRoutes: Int { get }

	/// True if the deep link was processed without any errors
	var wasSuccessful: Bool { get }

	/// True if the deep link processing was stopped by middleware
	var wasStoppedByMiddleware: Bool { get }

	/// True if any routes were found during processing
	var hasRoutes: Bool { get }

	/// True if any errors were encountered during processing
	var hasErrors: Bool { get }

	/// A concise summary of the deep link processing result
	var summary: String { get }
}

/// A protocol that allows objects to observe and respond to deep link coordinator events.
///
/// The `DeepLinkCoordinatorDelegate` protocol provides a way to monitor the deep link
/// processing lifecycle, enabling features like analytics, logging, error handling,
/// and custom business logic without modifying the coordinator itself.
///
/// ## Usage
///
/// ```swift
/// class DeepLinkAnalytics: DeepLinkCoordinatorDelegate {
///     func coordinator(_ coordinator: DeepLinkCoordinator<AppRoute>,
///                     willProcess url: URL) {
///         // Track deep link attempt
///         analytics.track("deep_link_attempted", parameters: ["url": url.absoluteString])
///     }
///
///     func coordinator(_ coordinator: DeepLinkCoordinator<AppRoute>,
///                     didProcess url: URL,
///                     result: DeepLinkResult<AppRoute>) {
///         // Track processing result
///         analytics.track("deep_link_processed", parameters: [
///             "success": result.wasSuccessful,
///             "execution_time": result.executionTime
///         ])
///     }
/// }
/// ```
///
/// ## Lifecycle Events
///
/// The delegate receives notifications for the following events:
/// - **willProcess**: Called before processing begins
/// - **didProcess**: Called after successful processing
/// - **didFailProcessing**: Called when processing fails
///
/// ## Thread Safety
///
/// All delegate methods are called on the main thread to ensure thread safety
/// and proper UI updates if needed.
public protocol DeepLinkCoordinatorDelegate: AnyObject, Sendable {
	/// Called before the coordinator begins processing a deep link URL.
	///
	/// This method is called immediately before the coordinator starts processing
	/// the URL through middleware, routing, and handling. Use this to:
	/// - Track deep link attempts
	/// - Log incoming URLs
	/// - Perform pre-processing validation
	/// - Update UI state (e.g., show loading indicator)
	///
	/// - Parameters:
	///   - coordinator: The coordinator that will process the URL
	///   - url: The deep link URL that will be processed
	func coordinator(
		_ coordinator: AnyObject,
		willProcess url: URL,
	)

	/// Called after the coordinator successfully processes a deep link URL.
	///
	/// This method is called after the coordinator has completed processing
	/// the URL, regardless of whether the processing was successful or not.
	/// Use this to:
	/// - Track processing results
	/// - Log success/failure metrics
	/// - Update analytics
	/// - Perform post-processing actions
	///
	/// - Parameters:
	///   - coordinator: The coordinator that processed the URL
	///   - url: The deep link URL that was processed
	///   - result: The result of the processing operation
	func coordinator(
		_ coordinator: AnyObject,
		didProcess url: URL,
		result: DeepLinkResultProtocol,
	)

	/// Called when the coordinator fails to process a deep link URL.
	///
	/// This method is called when an error occurs during processing that
	/// prevents the coordinator from completing the operation. Use this to:
	/// - Handle critical errors
	/// - Show error notifications to users
	/// - Log error details
	/// - Implement retry logic
	///
	/// - Parameters:
	///   - coordinator: The coordinator that failed to process the URL
	///   - url: The deep link URL that failed to process
	///   - error: The error that caused the processing to fail
	func coordinator(
		_ coordinator: AnyObject,
		didFailProcessing url: URL,
		error: Error,
	)
}

// MARK: - Default Implementations

public extension DeepLinkCoordinatorDelegate {
	/// Default implementation that does nothing.
	///
	/// This allows implementers to only override the methods they need.
	func coordinator(
		_: AnyObject,
		willProcess _: URL,
	) {
		// Default: do nothing
	}

	/// Default implementation that does nothing.
	///
	/// This allows implementers to only override the methods they need.
	func coordinator(
		_: AnyObject,
		didProcess _: URL,
		result _: DeepLinkResultProtocol,
	) {
		// Default: do nothing
	}

	/// Default implementation that does nothing.
	///
	/// This allows implementers to only override the methods they need.
	func coordinator(
		_: AnyObject,
		didFailProcessing _: URL,
		error _: Error,
	) {
		// Default: do nothing
	}
}
