//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Where a deep link came from.
///
/// The context is supplied by the entry point that received the link
/// (``DeepLinkCoordinator/handle(url:context:)``,
/// ``DeepLinkCoordinator/handle(activity:handoffActivityTypes:sceneID:)``,
/// `View.onDeepLink(_:)`) and travels with the URL through middleware to the
/// handler. It is a claim made by your own entry point, not something the
/// URL proves: a custom scheme can be opened by any app, so use the source
/// to *restrict* sensitive flows (for example to ``Source/universalLink``),
/// never to trust a link.
public struct DeepLinkContext: Sendable, Hashable {
	/// The channel that delivered a deep link.
	public enum Source: String, Sendable, Hashable, CaseIterable {
		/// A custom URL scheme (`myapp://…`), which any app can open.
		case customScheme
		/// A Universal Link verified against the app's associated domains.
		case universalLink
		/// An `NSUserActivity` continued from another device.
		case handoff
		/// A tap on a notification.
		case notification
		/// A Spotlight search result.
		case spotlight
		/// A Home Screen quick action.
		case shortcut
		/// An App Intent or Siri.
		case intent
		/// The entry point did not say, or the link was replayed from a
		/// readiness queue or pending-link store, which keep only the URL.
		case unknown
	}

	/// A context with an ``Source/unknown`` source and no origin details.
	public static let unknown = DeepLinkContext()

	/// The channel that delivered the link.
	public var source: Source

	/// The bundle identifier of the app that opened the link, when the system
	/// reports it (`UIScene.OpenURLOptions.sourceApplication`).
	public var sourceApplication: String?

	/// The identifier of the scene that received the link, for routing it
	/// back to the originating window.
	public var sceneID: String?

	/// Creates a context.
	///
	/// - Parameters:
	///   - source: The delivering channel. Defaults to ``Source/unknown``.
	///   - sourceApplication: The opening app's bundle identifier, if known.
	///   - sceneID: The receiving scene's identifier, if known.
	public init(source: Source = .unknown, sourceApplication: String? = nil, sceneID: String? = nil) {
		self.source = source
		self.sourceApplication = sourceApplication
		self.sceneID = sceneID
	}

	/// The context for a URL delivered by an "open URL" callback
	/// (`onOpenURL`, `scene(_:openURLContexts:)`): ``Source/customScheme``
	/// for custom schemes and ``Source/unknown`` for `http`/`https`.
	///
	/// An `http(s)` URL reaching an open-URL callback was not verified against
	/// the app's associated domains, so it is never claimed as a
	/// ``Source/universalLink``; only browsing-web user activities are.
	///
	/// - Parameters:
	///   - url: The opened URL.
	///   - sourceApplication: The opening app's bundle identifier, if known.
	///   - sceneID: The receiving scene's identifier, if known.
	/// - Returns: The inferred context.
	public static func openedURL(_ url: URL, sourceApplication: String? = nil, sceneID: String? = nil) -> DeepLinkContext {
		let isWeb = ["http", "https"].contains(url.scheme?.lowercased())
		return DeepLinkContext(
			source: isWeb ? .unknown : .customScheme,
			sourceApplication: sourceApplication,
			sceneID: sceneID,
		)
	}
}

/// A deep link URL together with the ``DeepLinkContext`` it arrived with.
///
/// Middleware receives and returns requests; a middleware that rewrites the
/// URL keeps the context with ``replacingURL(_:)``.
public struct DeepLinkRequest: Sendable, Hashable {
	/// The URL being processed.
	public var url: URL

	/// Where the link came from.
	public var context: DeepLinkContext

	/// Creates a request.
	///
	/// - Parameters:
	///   - url: The deep link URL.
	///   - context: Where it came from. Defaults to ``DeepLinkContext/unknown``.
	public init(url: URL, context: DeepLinkContext = .unknown) {
		self.url = url
		self.context = context
	}

	/// This request with `url` in place of its URL and the same context.
	public func replacingURL(_ url: URL) -> DeepLinkRequest {
		DeepLinkRequest(url: url, context: context)
	}
}
