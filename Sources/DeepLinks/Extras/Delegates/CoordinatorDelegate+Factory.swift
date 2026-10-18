//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

// MARK: - Static Factory Methods

public extension DeepLinkCoordinatorDelegate {
	/// Creates an analytics delegate that tracks deep link processing events.
	///
	/// This delegate automatically tracks deep link usage patterns, performance metrics,
	/// and error rates to help understand how users interact with deep links.
	///
	/// ## Usage
	///
	/// ```swift
	/// builder.delegate(.analytics(provider: myAnalyticsProvider))
	/// ```
	///
	/// ## Tracked Events
	///
	/// - **deep_link_attempted**: When deep link processing begins
	/// - **deep_link_processed**: When deep link processing completes
	/// - **deep_link_failed**: When deep link processing fails
	///
	/// - Parameters:
	///   - provider: The analytics provider to use for tracking events
	///   - privacy: How URLs and errors are tracked (default: ``DeepLinkLogPrivacy/redacted``)
	/// - Returns: A configured analytics delegate instance
	@MainActor
	static func analytics<R: DeepLinkRoute>(
		provider: AnalyticsProvider,
		privacy: DeepLinkLogPrivacy = .redacted,
	) -> DeepLinkAnalyticsDelegate<R> where Self == DeepLinkAnalyticsDelegate<R> {
		DeepLinkAnalyticsDelegate<R>(analyticsProvider: provider, privacy: privacy)
	}

	/// Creates a logging delegate that logs deep link processing events.
	///
	/// This delegate provides comprehensive logging for deep link processing lifecycle,
	/// making it easier to debug issues and monitor usage.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage
	/// builder.delegate(.logging())
	///
	/// // With debug logging enabled
	/// builder.delegate(.logging(enableDebugLogging: true))
	/// ```
	///
	/// ## Log Levels
	///
	/// - **Info**: Normal processing events
	/// - **Error**: Processing failures and errors
	/// - **Debug**: Detailed processing information (when enabled)
	///
	/// - Parameters:
	///   - enableDebugLogging: Whether to enable detailed debug logging (default: false)
	///   - privacy: How messages describe URLs and errors (default: ``DeepLinkLogPrivacy/redacted``)
	/// - Returns: A configured logging delegate instance
	@MainActor
	static func logging<R: DeepLinkRoute>(
		enableDebugLogging: Bool = false,
		privacy: DeepLinkLogPrivacy = .redacted,
	) -> DeepLinkLoggingDelegate<R> where Self == DeepLinkLoggingDelegate<R> {
		DeepLinkLoggingDelegate<R>(enableDebugLogging: enableDebugLogging, privacy: privacy)
	}

	#if canImport(UserNotifications) && !os(tvOS)
	/// Creates a notification delegate that shows user notifications for deep link events.
	///
	/// This delegate provides user feedback about deep link processing, particularly
	/// useful for debugging, user education, or when deep links fail to process.
	///
	/// - Note: Not available on tvOS, which does not display banner notifications.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage (shows only error notifications)
	/// builder.delegate(.notification())
	///
	/// // Show all notification types
	/// builder.delegate(.notification(
	///     showSuccess: true,
	///     showErrors: true,
	///     showInfo: true
	/// ))
	/// ```
	///
	/// ## Notification Types
	///
	/// - **Success**: When deep links are processed successfully
	/// - **Error**: When deep links fail to process (shown by default)
	/// - **Info**: General information about deep link processing
	///
	/// - Parameters:
	///   - showSuccess: Whether to show notifications for successful processing (default: false)
	///   - showErrors: Whether to show notifications for processing errors (default: true)
	///   - showInfo: Whether to show general info notifications (default: false)
	///   - presenter: The presenter that receives each scheduled notification.
	///     Defaults to ``DefaultDeepLinkNotificationPresenter``; inject a test
	///     double in unit tests to suppress real system notifications.
	///   - errorDetail: How much error text failure notifications show
	///     (default: ``DeepLinkNotificationErrorDetail/redacted``; `.full` shows full URLs).
	/// - Returns: A configured notification delegate instance
	@MainActor
	static func notification<R: DeepLinkRoute>(
		showSuccess: Bool = false,
		showErrors: Bool = true,
		showInfo: Bool = false,
		presenter: any DeepLinkNotificationPresenter = DefaultDeepLinkNotificationPresenter(),
		errorDetail: DeepLinkNotificationErrorDetail = .redacted,
	) -> DeepLinkNotificationDelegate<R> where Self == DeepLinkNotificationDelegate<R> {
		DeepLinkNotificationDelegate<R>(
			showSuccessNotifications: showSuccess,
			showErrorNotifications: showErrors,
			showInfoNotifications: showInfo,
			presenter: presenter,
			errorDetail: errorDetail,
		)
	}
	#endif
}
