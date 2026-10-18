//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

public extension DeepLinkCoordinator {
	/// Processes a deep link delivered via `NSUserActivity`.
	///
	/// Only two kinds of activity are accepted:
	///
	/// - ``Foundation/NSUserActivityTypeBrowsingWeb`` (Universal Links), handled
	///   with a ``DeepLinkContext/Source/universalLink`` source;
	/// - an activity whose `activityType` is in `handoffActivityTypes`, handled
	///   with a ``DeepLinkContext/Source/handoff`` source.
	///
	/// Any other activity type (Spotlight, App Intents, undeclared Handoff
	/// types) and any activity without a `webpageURL` is rejected: the method
	/// returns `nil` without running the pipeline, so delegates and analytics
	/// observers are not notified. `referrerURL` is intentionally **not**
	/// consulted: for `NSUserActivityTypeBrowsingWeb` it points at the
	/// referring web page, not the deep link itself.
	///
	/// This method is main-actor isolated so it can accept the non-`Sendable`
	/// `NSUserActivity` from UI callbacks without a pre-extraction dance.
	///
	/// ## Example
	///
	/// ```swift
	/// // UIKit scene delegate (already main-actor)
	/// func scene(_ scene: UIScene, continue activity: NSUserActivity) {
	///     Task {
	///         await coordinator.handle(
	///             activity: activity,
	///             handoffActivityTypes: ["com.example.viewing-product"],
	///             sceneID: scene.session.persistentIdentifier
	///         )
	///     }
	/// }
	/// ```
	///
	/// - Parameters:
	///   - activity: The user activity carrying the URL.
	///   - handoffActivityTypes: Activity types accepted as Handoff, usually the
	///     `NSUserActivityTypes` your `Info.plist` declares. Defaults to none.
	///   - sceneID: The receiving scene's identifier, if known.
	/// - Returns: The processing result, or `nil` when the activity is rejected.
	@MainActor
	@discardableResult
	func handle(
		activity: NSUserActivity,
		handoffActivityTypes: Set<String> = [],
		sceneID: String? = nil,
	) async -> DeepLinkResult<Route>? {
		guard let url = activity.webpageURL,
		      let source = Self.source(ofActivityType: activity.activityType, handoffActivityTypes: handoffActivityTypes)
		else { return nil }
		return await handle(url: url, context: DeepLinkContext(source: source, sceneID: sceneID))
	}
}

private extension DeepLinkCoordinator {
	static func source(ofActivityType type: String, handoffActivityTypes: Set<String>) -> DeepLinkContext.Source? {
		if type == NSUserActivityTypeBrowsingWeb {
			return .universalLink
		}
		return handoffActivityTypes.contains(type) ? .handoff : nil
	}
}
