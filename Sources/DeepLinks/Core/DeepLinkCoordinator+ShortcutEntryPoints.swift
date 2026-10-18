//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(UIKit) && (os(iOS) || os(visionOS))

import Foundation
import UIKit

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
