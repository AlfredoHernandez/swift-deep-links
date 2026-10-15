//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(UserNotifications) && !os(tvOS)

import Foundation
#if canImport(UIKit) && (os(iOS) || os(visionOS))
import UIKit
#endif
import UserNotifications

public extension DeepLinkCoordinator {
	/// Processes the deep link carried by a tapped notification, with a
	/// ``DeepLinkContext/Source/notification`` source.
	///
	/// The URL is read from `content.userInfo[urlKey]` (a `String` or `URL`
	/// with a scheme). A dismissed notification
	/// (`UNNotificationDismissActionIdentifier`), or one without a URL,
	/// returns `nil` without running the pipeline.
	///
	/// ```swift
	/// func userNotificationCenter(
	///     _ center: UNUserNotificationCenter,
	///     didReceive response: UNNotificationResponse
	/// ) async {
	///     await coordinator.handle(notificationResponse: response)
	/// }
	/// ```
	///
	/// - Parameters:
	///   - response: The user's response to the notification.
	///   - urlKey: The `userInfo` key holding the URL. Defaults to `"deepLink"`.
	///   - sceneID: The scene to route to. Defaults to the response's target
	///     scene where UIKit provides one.
	/// - Returns: The processing result, or `nil` when there is nothing to handle.
	@MainActor
	@discardableResult
	func handle(
		notificationResponse response: UNNotificationResponse,
		urlKey: String = "deepLink",
		sceneID: String? = nil,
	) async -> DeepLinkResult<Route>? {
		await handle(
			notificationUserInfo: response.notification.request.content.userInfo,
			actionIdentifier: response.actionIdentifier,
			urlKey: urlKey,
			sceneID: sceneID ?? Self.targetSceneID(of: response),
		)
	}

	/// Processes the deep link in a notification payload, with a
	/// ``DeepLinkContext/Source/notification`` source.
	///
	/// Use it when you receive the payload outside
	/// `userNotificationCenter(_:didReceive:)`; see
	/// ``handle(notificationResponse:urlKey:sceneID:)``.
	///
	/// - Parameters:
	///   - userInfo: The notification's `userInfo`.
	///   - actionIdentifier: The chosen action; the dismiss action is ignored.
	///     Defaults to `UNNotificationDefaultActionIdentifier`.
	///   - urlKey: The key holding the URL. Defaults to `"deepLink"`.
	///   - sceneID: The scene to route to, if known.
	/// - Returns: The processing result, or `nil` when there is nothing to handle.
	@MainActor
	@discardableResult
	func handle(
		notificationUserInfo userInfo: [AnyHashable: Any],
		actionIdentifier: String = UNNotificationDefaultActionIdentifier,
		urlKey: String = "deepLink",
		sceneID: String? = nil,
	) async -> DeepLinkResult<Route>? {
		guard actionIdentifier != UNNotificationDismissActionIdentifier,
		      let url = DeepLinkPayloadURL.url(from: userInfo, key: urlKey)
		else { return nil }
		return await handle(url: url, context: DeepLinkContext(source: .notification, sceneID: sceneID))
	}
}

private extension DeepLinkCoordinator {
	@MainActor
	static func targetSceneID(of response: UNNotificationResponse) -> String? {
		#if canImport(UIKit) && (os(iOS) || os(visionOS))
		response.targetScene?.session.persistentIdentifier
		#else
		nil
		#endif
	}
}

#endif
