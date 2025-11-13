//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import UserNotifications

/// A delegate implementation that shows user notifications for deep link processing events.
///
/// This delegate provides user feedback about deep link processing, particularly
/// useful for debugging, user education, or when deep links fail to process.
///
/// ## Usage
///
/// ```swift
/// let notificationDelegate = DeepLinkNotificationDelegate()
/// coordinator.delegate = notificationDelegate
/// ```
///
/// ## Notification Types
///
/// - **Success**: When deep links are processed successfully (optional)
/// - **Error**: When deep links fail to process (recommended)
/// - **Info**: General information about deep link processing (optional)
public final class DeepLinkNotificationDelegate: DeepLinkCoordinatorDelegate, @unchecked Sendable {
    private let showSuccessNotifications: Bool
    private let showErrorNotifications: Bool
    private let showInfoNotifications: Bool

    /// Creates a new notification delegate.
    ///
    /// - Parameters:
    ///   - showSuccessNotifications: Whether to show notifications for successful processing (default: false)
    ///   - showErrorNotifications: Whether to show notifications for processing errors (default: true)
    ///   - showInfoNotifications: Whether to show general info notifications (default: false)
    public init(
        showSuccessNotifications: Bool = false,
        showErrorNotifications: Bool = true,
        showInfoNotifications: Bool = false,
    ) {
        self.showSuccessNotifications = showSuccessNotifications
        self.showErrorNotifications = showErrorNotifications
        self.showInfoNotifications = showInfoNotifications
    }

    public func coordinator(
        _: AnyObject,
        willProcess url: URL,
    ) {
        guard showInfoNotifications else { return }

        Task {
            await showNotification(
                title: "Deep Link Processing",
                body: "Opening: \(url.host() ?? "Unknown")",
                identifier: "deeplink-processing-\(url.hashValue)",
            )
        }
    }

    public func coordinator(
        _: AnyObject,
        didProcess url: URL,
        result: DeepLinkResultProtocol,
    ) {
        if result.wasSuccessful, showSuccessNotifications {
            Task {
                await showNotification(
                    title: "Deep Link Opened",
                    body: "Successfully opened link",
                    identifier: "deeplink-success-\(url.hashValue)",
                )
            }
        } else if !result.wasSuccessful, showErrorNotifications {
            Task {
                let errorMessage = result.errors.first?.localizedDescription ?? "Unknown error"
                await showNotification(
                    title: "Deep Link Failed",
                    body: "Could not open link: \(errorMessage)",
                    identifier: "deeplink-error-\(url.hashValue)",
                )
            }
        }
    }

    public func coordinator(
        _: AnyObject,
        didFailProcessing url: URL,
        error: Error,
    ) {
        guard showErrorNotifications else { return }

        Task {
            await showNotification(
                title: "Deep Link Error",
                body: "Failed to process link: \(error.localizedDescription)",
                identifier: "deeplink-critical-error-\(url.hashValue)",
            )
        }
    }

    /// Shows a local notification to the user.
    ///
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body
    ///   - identifier: The unique identifier for the notification
    private func showNotification(title: String, body: String, identifier: String) async {
        // In test environments, just print the notification instead of trying to show it
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            print("NOTIFICATION: \(title) - \(body)")
            return
        }
        #endif

        do {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil, // Show immediately
            )

            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Silently fail if notifications are not authorized or available
            print("NOTIFICATION: \(title) - \(body)")
        }
    }
}
