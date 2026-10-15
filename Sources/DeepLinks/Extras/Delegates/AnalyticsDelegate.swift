//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// let analyticsDelegate = DeepLinkAnalyticsDelegate<AppRoute>(analyticsProvider: yourAnalyticsProvider)
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
@MainActor
public final class DeepLinkAnalyticsDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
	private let analyticsProvider: AnalyticsProvider
	private let privacy: DeepLinkLogPrivacy

	/// Creates a new analytics delegate.
	///
	/// - Parameters:
	///   - analyticsProvider: The analytics provider to use for tracking events
	///   - privacy: How URLs and error descriptions are tracked. Defaults to
	///     ``DeepLinkLogPrivacy/redacted``; non-framework errors are described by type name.
	public init(analyticsProvider: AnalyticsProvider, privacy: DeepLinkLogPrivacy = .redacted) {
		self.analyticsProvider = analyticsProvider
		self.privacy = privacy
	}

	/// Tracks `deep_link_attempted` with the URL envelope (redacted per `privacy`).
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		willProcess url: URL,
	) {
		analyticsProvider.track(
			"deep_link_attempted",
			parameters: AnalyticsEventBuilder.parameters(for: privacy.redact(url), detail: .full),
		)
	}

	/// Tracks `deep_link_processed` with the outcome: `success`,
	/// `execution_time`, route counts, `errors_count`,
	/// `was_stopped_by_middleware` and, when there are errors,
	/// `error_descriptions` described per `privacy`.
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didProcess url: URL,
		result: DeepLinkResult<Route>,
	) {
		var parameters = AnalyticsEventBuilder.parameters(for: privacy.redact(url), detail: .full)
		parameters["success"] = result.wasSuccessful
		parameters["execution_time"] = result.executionTime
		parameters["successful_routes"] = result.successfulRoutes
		parameters["failed_routes"] = result.failedRoutes
		parameters["errors_count"] = result.errors.count
		parameters["was_stopped_by_middleware"] = result.wasStoppedByMiddleware

		if !result.errors.isEmpty {
			parameters["error_descriptions"] = result.errors.map { privacy.describe($0) }
		}

		analyticsProvider.track("deep_link_processed", parameters: parameters)
	}

	/// Tracks `deep_link_failed` for a link that middleware or routing
	/// rejected, with `error_description` (per `privacy`), `error_domain` and
	/// `error_code`. Handler failures arrive in `didProcess` instead.
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didFailProcessing url: URL,
		error: Error,
	) {
		var parameters = AnalyticsEventBuilder.parameters(for: privacy.redact(url), detail: .full)
		parameters["error_description"] = privacy.describe(error)
		parameters["error_domain"] = (error as NSError).domain
		parameters["error_code"] = (error as NSError).code
		analyticsProvider.track("deep_link_failed", parameters: parameters)
	}
}
