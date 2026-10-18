//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import os

/// Routes each deep link to the handler of the scene (window) it arrived in.
///
/// Multi-window apps (iPadOS, macOS, visionOS) share one coordinator but
/// navigate per window. Pass the receiving scene's identifier in the
/// ``DeepLinkContext/sceneID`` (every entry point takes a `sceneID`, and
/// `View.onDeepLink(_:sceneID:)` sets it), register each scene's navigation
/// handler under that identifier, and use this router as the coordinator's
/// handler. The scene handler receives the full context.
///
/// Links without a scene, or from a scene with no registered handler (it was
/// closed before a queued or pending link was replayed), go to `fallback`, typically the handler
/// of the frontmost scene. Without a fallback they fail with
/// ``DeepLinkError/handlerError(message:underlyingError:)``.
///
/// ```swift
/// let router = SceneRoutingHandler<AppRoute>(fallback: MainWindowHandler())
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .parser(parser)
///     .handler(router)
///     .build()
///
/// // UIKit: in scene(_:willConnectTo:options:)
/// router.register(SceneNavigator(window: window), forScene: session.persistentIdentifier)
/// // and in sceneDidDisconnect(_:)
/// router.unregister(scene: scene.session.persistentIdentifier)
/// ```
///
/// - Thread Safety: Registration is lock-protected; safe from any task.
public final class SceneRoutingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
	/// The message of the error thrown when no scene handler or fallback can take a route.
	public static var noSceneHandlerMessage: String {
		"No handler registered for the link's scene"
	}

	private let handlers = OSAllocatedUnfairLock<[String: any DeepLinkHandler<Route>]>(initialState: [:])
	private let fallback: (any DeepLinkHandler<Route>)?

	/// Creates a router.
	///
	/// - Parameter fallback: Handles links without a registered scene. Defaults to `nil`.
	public init(fallback: (any DeepLinkHandler<Route>)? = nil) {
		self.fallback = fallback
	}

	/// The identifiers of the scenes with a registered handler.
	public var registeredSceneIDs: Set<String> {
		handlers.withLock { Set($0.keys) }
	}

	/// Routes links from scene `sceneID` to `handler`, replacing any earlier registration.
	public func register(_ handler: any DeepLinkHandler<Route>, forScene sceneID: String) {
		handlers.withLock { $0[sceneID] = handler }
	}

	/// Stops routing links to scene `sceneID`; later links from it go to the fallback.
	public func unregister(scene sceneID: String) {
		handlers.withLock { $0[sceneID] = nil }
	}

	/// Runs `route` on the handler registered for `context.sceneID`, or on the
	/// fallback when the link has no scene or its scene has no handler.
	///
	/// - Throws: ``DeepLinkError/handlerError(message:underlyingError:)`` with
	///   ``noSceneHandlerMessage`` when there is neither, or whatever the chosen handler throws.
	public func handle(_ route: Route, context: DeepLinkContext) async throws {
		let sceneHandler = context.sceneID.flatMap { sceneID in handlers.withLock { $0[sceneID] } }
		guard let handler = sceneHandler ?? fallback else {
			throw DeepLinkError.handlerError(message: Self.noSceneHandlerMessage, underlyingError: nil)
		}
		try await handler.handle(route, context: context)
	}
}
