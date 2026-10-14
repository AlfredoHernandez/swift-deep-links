//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
#if canImport(CoreSpotlight) && !os(tvOS)
import CoreSpotlight
#endif
#if canImport(UserNotifications) && !os(tvOS)
import UserNotifications
#endif
#if canImport(UIKit) && (os(iOS) || os(visionOS))
import UIKit
#endif

// Every entry point here extracts one absolute URL from its payload and
// delegates to `handle(url:context:)`; no other payload value reaches the
// pipeline, so middleware sees these links like any other untrusted URL
// (a payload opening a path that `SignedLinkMiddleware` protects must carry
// the signed URL).

// MARK: - Notifications

#if canImport(UserNotifications) && !os(tvOS)

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

// MARK: - Spotlight

#if canImport(CoreSpotlight) && !os(tvOS)

public extension DeepLinkCoordinator {
	/// Processes a Spotlight result continued as a `CSSearchableItemActionType`
	/// activity, with a ``DeepLinkContext/Source/spotlight`` source.
	///
	/// The item's identifier (`userInfo[CSSearchableItemActivityIdentifier]`)
	/// is mapped to a URL by `urlForIdentifier`. Other activity types, a
	/// missing identifier or an unmappable one return `nil` without running
	/// the pipeline.
	///
	/// ```swift
	/// .onContinueUserActivity(CSSearchableItemActionType) { activity in
	///     Task { await coordinator.handle(searchableItemActivity: activity) }
	/// }
	/// ```
	///
	/// - Parameters:
	///   - activity: The continued activity.
	///   - sceneID: The receiving scene's identifier, if known.
	///   - urlForIdentifier: Maps the item's `uniqueIdentifier` to a URL.
	///     Defaults to parsing the identifier itself as an absolute URL.
	/// - Returns: The processing result, or `nil` when there is nothing to handle.
	@MainActor
	@discardableResult
	func handle(
		searchableItemActivity activity: NSUserActivity,
		sceneID: String? = nil,
		urlForIdentifier: (String) -> URL? = { URL(string: $0) },
	) async -> DeepLinkResult<Route>? {
		guard activity.activityType == CSSearchableItemActionType,
		      let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
		      let url = urlForIdentifier(identifier).flatMap(DeepLinkPayloadURL.absolute)
		else { return nil }
		return await handle(url: url, context: DeepLinkContext(source: .spotlight, sceneID: sceneID))
	}

	/// Processes the Spotlight item `identifier`, with a
	/// ``DeepLinkContext/Source/spotlight`` source.
	///
	/// - Parameters:
	///   - identifier: The searchable item's `uniqueIdentifier`.
	///   - sceneID: The receiving scene's identifier, if known.
	///   - urlForIdentifier: Maps the identifier to a URL. Defaults to parsing
	///     the identifier itself as an absolute URL.
	/// - Returns: The processing result, or `nil` when no URL could be derived.
	@MainActor
	@discardableResult
	func handle(
		searchableItemIdentifier identifier: String,
		sceneID: String? = nil,
		urlForIdentifier: (String) -> URL? = { URL(string: $0) },
	) async -> DeepLinkResult<Route>? {
		guard let url = urlForIdentifier(identifier).flatMap(DeepLinkPayloadURL.absolute) else { return nil }
		return await handle(url: url, context: DeepLinkContext(source: .spotlight, sceneID: sceneID))
	}
}

#endif

// MARK: - Home Screen Quick Actions

#if os(iOS)

public extension DeepLinkCoordinator {
	/// Processes a Home Screen quick action, with a
	/// ``DeepLinkContext/Source/shortcut`` source.
	///
	/// The URL is `shortcutItem.userInfo[urlKey]` or, when absent, the item's
	/// `type` if it is an absolute URL. A shortcut without a URL returns
	/// `nil` without running the pipeline.
	///
	/// ```swift
	/// func windowScene(
	///     _ windowScene: UIWindowScene,
	///     performActionFor shortcutItem: UIApplicationShortcutItem
	/// ) async -> Bool {
	///     await coordinator.handle(
	///         shortcutItem: shortcutItem,
	///         sceneID: windowScene.session.persistentIdentifier
	///     )?.wasSuccessful ?? false
	/// }
	/// ```
	///
	/// - Parameters:
	///   - shortcutItem: The selected quick action.
	///   - urlKey: The `userInfo` key holding the URL. Defaults to `"deepLink"`.
	///   - sceneID: The receiving scene's identifier, if known.
	/// - Returns: The processing result, or `nil` when there is nothing to handle.
	@MainActor
	@discardableResult
	func handle(
		shortcutItem: UIApplicationShortcutItem,
		urlKey: String = "deepLink",
		sceneID: String? = nil,
	) async -> DeepLinkResult<Route>? {
		guard let url = DeepLinkPayloadURL.shortcutURL(type: shortcutItem.type, userInfo: shortcutItem.userInfo, key: urlKey) else {
			return nil
		}
		return await handle(url: url, context: DeepLinkContext(source: .shortcut, sceneID: sceneID))
	}
}

#endif
