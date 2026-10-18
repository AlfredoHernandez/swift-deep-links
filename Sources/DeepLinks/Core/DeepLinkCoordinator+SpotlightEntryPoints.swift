//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CoreSpotlight) && !os(tvOS)

import CoreSpotlight
import Foundation

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
