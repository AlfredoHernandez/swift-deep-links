//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

// `UserNotifications` is available on iOS, macOS, watchOS, and visionOS but tvOS
// does not display banner notifications, so `DeepLinkNotificationDelegate` is
// gated out of tvOS builds. Consumers targeting tvOS should use a different
// delegate (e.g. `DeepLinkLoggingDelegate` or a custom one) for user feedback.
#if canImport(UserNotifications) && !os(tvOS)

import Foundation
import os
import OSLog
import UserNotifications

/// Classifies the kind of lifecycle event that triggered a notification.
///
/// Passed to ``DeepLinkNotificationPresenter/present(kind:title:body:identifier:)``
/// so custom presenters can branch on severity (icon colour, toast shape,
/// dispatch channel, …) without having to parse the title string or the
/// identifier prefix.
public enum DeepLinkNotificationKind: Sendable {
	/// A deep link was processed successfully.
	case success
	/// A deep link failed to process or ended with errors.
	case failure
	/// A neutral lifecycle event (for example, processing started).
	case info
}

/// Controls how much of an error's text a failure notification shows.
///
/// Notifications can appear on the lock screen, so prefer ``redacted`` or
/// ``generic`` when deep links may carry tokens, codes or personal data.
public struct DeepLinkNotificationErrorDetail: Sendable {
	private let describe: @Sendable ((any Error)?) -> String?

	private init(_ describe: @escaping @Sendable ((any Error)?) -> String?) {
		self.describe = describe
	}

	/// Shows the error's `localizedDescription`, including any URL it carries.
	public static let full = DeepLinkNotificationErrorDetail { error in
		error?.localizedDescription ?? "Unknown error"
	}

	/// Shows ``DeepLinkError/redactedDescription`` for framework errors and
	/// only the type name of other errors.
	public static let redacted = redacted(using: URLRedactor())

	/// Shows no error text at all.
	public static let generic = DeepLinkNotificationErrorDetail { _ in nil }

	/// Shows ``DeepLinkError/redactedDescription(using:)`` for framework errors
	/// and only the type name of other errors.
	///
	/// - Parameter redactor: The redactor applied to URLs and parameter values.
	/// - Returns: A redacting error detail.
	public static func redacted(using redactor: URLRedactor) -> DeepLinkNotificationErrorDetail {
		DeepLinkNotificationErrorDetail { error in
			guard let error else { return "Unknown error" }
			return (error as? DeepLinkError)?.redactedDescription(using: redactor) ?? String(describing: type(of: error))
		}
	}

	func message(_ prefix: String, for error: (any Error)?) -> String {
		describe(error).map { "\(prefix): \($0)" } ?? prefix
	}
}

/// Presents deep-link lifecycle notifications to the user.
///
/// ``DeepLinkNotificationDelegate`` delegates the actual notification
/// scheduling to an object conforming to this protocol. The default
/// ``DefaultDeepLinkNotificationPresenter`` routes requests to
/// `UNUserNotificationCenter`; tests and custom UIs can substitute a stub
/// presenter to avoid real system notifications or to render through a
/// different surface (toast, in-app banner, etc.).
public protocol DeepLinkNotificationPresenter: Sendable {
	/// Presents a notification for a lifecycle event.
	///
	/// - Parameters:
	///   - kind: Classifies the lifecycle event so presenters can branch on
	///     severity without inspecting `title` or `identifier`.
	///   - title: The notification's headline.
	///   - body: The notification's detail text.
	///   - identifier: A unique identifier used to deduplicate and replace
	///     pending notifications.
	/// - Throws: Any scheduling error raised by the underlying sink.
	func present(
		kind: DeepLinkNotificationKind,
		title: String,
		body: String,
		identifier: String,
	) async throws
}

/// The default ``DeepLinkNotificationPresenter`` implementation, backed by
/// `UNUserNotificationCenter.current()`.
///
/// Use this when you want the framework to display real system notifications.
/// The default implementation ignores ``DeepLinkNotificationKind`` — all kinds
/// go through the same `UNUserNotificationCenter` sink — but the parameter is
/// still forwarded to the protocol so custom presenters can differentiate.
/// Inject a different presenter (for example in unit tests) when you want to
/// observe or suppress the notification traffic without hitting the system
/// notification center.
public struct DefaultDeepLinkNotificationPresenter: DeepLinkNotificationPresenter {
	/// Creates a presenter that posts to `UNUserNotificationCenter.current()`.
	/// The app must have notification authorization, or every presentation
	/// fails and is logged by the delegate.
	public init() {}

	/// Posts an immediate local notification with the default sound; a
	/// pending notification with the same `identifier` is replaced. `kind` is
	/// ignored.
	///
	/// - Throws: The error `UNUserNotificationCenter` reports, such as missing authorization.
	public func present(
		kind _: DeepLinkNotificationKind,
		title: String,
		body: String,
		identifier: String,
	) async throws {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default

		let request = UNNotificationRequest(
			identifier: identifier,
			content: content,
			trigger: nil,
		)

		try await UNUserNotificationCenter.current().add(request)
	}
}

/// A delegate implementation that shows user notifications for deep link processing events.
///
/// This delegate provides user feedback about deep link processing, particularly
/// useful for debugging, user education, or when deep links fail to process.
///
/// ## Usage
///
/// ```swift
/// let notificationDelegate = DeepLinkNotificationDelegate<AppRoute>()
/// coordinator.delegate = notificationDelegate
/// ```
///
/// ## Notification Types
///
/// - **Success**: When deep links are processed successfully (optional)
/// - **Error**: When deep links fail to process (recommended)
/// - **Info**: General information about deep link processing (optional)
///
/// ## Custom presentation
///
/// Pass a custom ``DeepLinkNotificationPresenter`` to redirect notifications
/// through an in-app UI or to capture them in tests without hitting
/// `UNUserNotificationCenter`.
///
/// ## Lifetime
///
/// In-flight notification tasks are tracked internally and cancelled when the
/// delegate is deallocated, so releasing the delegate during teardown (e.g.,
/// logout, test reset) stops any scheduling that has not yet reached the
/// presenter.
@MainActor
public final class DeepLinkNotificationDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
	private let showSuccessNotifications: Bool
	private let showErrorNotifications: Bool
	private let showInfoNotifications: Bool
	private let presenter: any DeepLinkNotificationPresenter
	private let errorDetail: DeepLinkNotificationErrorDetail
	private let logger = Logger(subsystem: "swift-deep-links", category: "DeepLinkNotificationDelegate")
	private let pendingTasks = OSAllocatedUnfairLock<[UUID: Task<Void, Never>]>(initialState: [:])

	/// Creates a new notification delegate.
	///
	/// - Parameters:
	///   - showSuccessNotifications: Whether to show notifications for successful processing (default: false)
	///   - showErrorNotifications: Whether to show notifications for processing errors (default: true)
	///   - showInfoNotifications: Whether to show general info notifications (default: false)
	///   - presenter: The presenter that receives each scheduled notification.
	///     Defaults to ``DefaultDeepLinkNotificationPresenter``, which forwards
	///     to `UNUserNotificationCenter`. Inject a test double in unit tests to
	///     suppress real system notifications.
	///   - errorDetail: How much error text failure notifications show. Defaults to
	///     ``DeepLinkNotificationErrorDetail/redacted`` because notifications can
	///     appear on the lock screen; `.full` shows full URLs.
	public init(
		showSuccessNotifications: Bool = false,
		showErrorNotifications: Bool = true,
		showInfoNotifications: Bool = false,
		presenter: any DeepLinkNotificationPresenter = DefaultDeepLinkNotificationPresenter(),
		errorDetail: DeepLinkNotificationErrorDetail = .redacted,
	) {
		self.showSuccessNotifications = showSuccessNotifications
		self.showErrorNotifications = showErrorNotifications
		self.showInfoNotifications = showInfoNotifications
		self.presenter = presenter
		self.errorDetail = errorDetail
	}

	deinit {
		pendingTasks.withLock { tasks in
			for task in tasks.values {
				task.cancel()
			}
			tasks.removeAll()
		}
	}

	/// Shows an info notification naming the link's host, only when
	/// `showInfoNotifications` is on.
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		willProcess url: URL,
	) {
		guard showInfoNotifications else { return }

		schedule { [weak self] in
			await self?.showNotification(
				kind: .info,
				title: "Deep Link Processing",
				body: "Opening: \(url.host() ?? "Unknown")",
				identifier: "deeplink-processing-\(url.hashValue)",
			)
		}
	}

	/// Shows a success notification for a successful link when
	/// `showSuccessNotifications` is on, or a failure notification (detail per
	/// `errorDetail`) for an unsuccessful one when `showErrorNotifications` is
	/// on. A link stopped by middleware counts as unsuccessful.
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didProcess url: URL,
		result: DeepLinkResult<Route>,
	) {
		if result.wasSuccessful, showSuccessNotifications {
			schedule { [weak self] in
				await self?.showNotification(
					kind: .success,
					title: "Deep Link Opened",
					body: "Successfully opened link",
					identifier: "deeplink-success-\(url.hashValue)",
				)
			}
		} else if !result.wasSuccessful, showErrorNotifications {
			let body = errorDetail.message("Could not open link", for: result.errors.first)
			schedule { [weak self] in
				await self?.showNotification(
					kind: .failure,
					title: "Deep Link Failed",
					body: body,
					identifier: "deeplink-error-\(url.hashValue)",
				)
			}
		}
	}

	/// Shows a failure notification (detail per `errorDetail`) for a link
	/// middleware or routing rejected, when `showErrorNotifications` is on.
	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didFailProcessing url: URL,
		error: Error,
	) {
		guard showErrorNotifications else { return }

		let body = errorDetail.message("Failed to process link", for: error)
		schedule { [weak self] in
			await self?.showNotification(
				kind: .failure,
				title: "Deep Link Error",
				body: body,
				identifier: "deeplink-critical-error-\(url.hashValue)",
			)
		}
	}

	/// Spawns a MainActor-isolated notification task tracked in `pendingTasks` so
	/// it can be cancelled from `deinit` if the delegate is released before the
	/// notification reaches the presenter.
	///
	/// The insert into `pendingTasks` happens after the `Task` is constructed;
	/// correctness relies on a MainActor invariant: `schedule` itself runs on
	/// the main actor, the task body is also `@MainActor`-isolated, so the
	/// body cannot begin executing (and call its self-removal line) until the
	/// current MainActor frame — which does the insert right after the Task
	/// literal — finishes. Any future refactor that drops `@MainActor` from
	/// the body or switches to a detached task must insert first, then spawn.
	private func schedule(_ body: @MainActor @Sendable @escaping () async -> Void) {
		let id = UUID()
		let lock = pendingTasks
		let task = Task { @MainActor in
			await body()
			lock.withLock { $0[id] = nil }
		}
		pendingTasks.withLock { $0[id] = task }
	}

	/// Forwards the notification payload to the configured presenter and logs any failure.
	///
	/// - Parameters:
	///   - kind: The lifecycle classification for the event.
	///   - title: The notification title
	///   - body: The notification body
	///   - identifier: The unique identifier for the notification
	private func showNotification(
		kind: DeepLinkNotificationKind,
		title: String,
		body: String,
		identifier: String,
	) async {
		do {
			try await presenter.present(kind: kind, title: title, body: body, identifier: identifier)
		} catch {
			logger.error("Failed to present notification '\(title)': \(error.localizedDescription)")
		}
	}
}

#endif
