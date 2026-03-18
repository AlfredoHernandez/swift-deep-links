//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

// MARK: - Static Factory Methods

public extension DeepLinkCoordinatorDelegate where Self == DeepLinkAnalyticsDelegate {
	/// Creates an analytics delegate that tracks deep link processing events.
	///
	/// This delegate automatically tracks deep link usage patterns, performance metrics,
	/// and error rates to help understand how users interact with deep links.
	///
	/// ## Usage
	///
	/// ```swift
	/// coordinator.delegate = .analytics(provider: myAnalyticsProvider)
	/// ```
	///
	/// ## Tracked Events
	///
	/// - **deep_link_attempted**: When deep link processing begins
	/// - **deep_link_processed**: When deep link processing completes
	/// - **deep_link_failed**: When deep link processing fails
	///
	/// - Parameter provider: The analytics provider to use for tracking events
	/// - Returns: A configured analytics delegate instance
	static func analytics(
		provider: AnalyticsProvider,
	) -> DeepLinkAnalyticsDelegate {
		DeepLinkAnalyticsDelegate(analyticsProvider: provider)
	}
}

public extension DeepLinkCoordinatorDelegate where Self == DeepLinkLoggingDelegate {
	/// Creates a logging delegate that logs deep link processing events.
	///
	/// This delegate provides comprehensive logging for deep link processing lifecycle,
	/// making it easier to debug issues and monitor usage.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage
	/// coordinator.delegate = .logging()
	///
	/// // With debug logging enabled
	/// coordinator.delegate = .logging(enableDebugLogging: true)
	/// ```
	///
	/// ## Log Levels
	///
	/// - **Info**: Normal processing events
	/// - **Error**: Processing failures and errors
	/// - **Debug**: Detailed processing information (when enabled)
	///
	/// - Parameter enableDebugLogging: Whether to enable detailed debug logging (default: false)
	/// - Returns: A configured logging delegate instance
	static func logging(
		enableDebugLogging: Bool = false,
	) -> DeepLinkLoggingDelegate {
		DeepLinkLoggingDelegate(enableDebugLogging: enableDebugLogging)
	}
}

public extension DeepLinkCoordinatorDelegate where Self == DeepLinkNotificationDelegate {
	/// Creates a notification delegate that shows user notifications for deep link events.
	///
	/// This delegate provides user feedback about deep link processing, particularly
	/// useful for debugging, user education, or when deep links fail to process.
	///
	/// ## Usage
	///
	/// ```swift
	/// // Basic usage (shows only error notifications)
	/// coordinator.delegate = .notification()
	///
	/// // Show all notification types
	/// coordinator.delegate = .notification(
	///     showSuccess: true,
	///     showErrors: true,
	///     showInfo: true
	/// )
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
	/// - Returns: A configured notification delegate instance
	static func notification(
		showSuccess: Bool = false,
		showErrors: Bool = true,
		showInfo: Bool = false,
	) -> DeepLinkNotificationDelegate {
		DeepLinkNotificationDelegate(
			showSuccessNotifications: showSuccess,
			showErrorNotifications: showErrors,
			showInfoNotifications: showInfo,
		)
	}
}
