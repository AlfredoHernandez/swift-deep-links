//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(SwiftUI)

import Foundation
import SwiftUI

public extension View {
	/// Routes incoming deep links and Universal Links to a coordinator.
	///
	/// Attaches both the SwiftUI `onOpenURL(perform:)` handler (for custom URL schemes
	/// opened from another app) and the `onContinueUserActivity(_:perform:)` handler
	/// for `NSUserActivityTypeBrowsingWeb` (for Universal Links) to a single view. Each
	/// incoming URL is forwarded to the given coordinator on a detached task so the view
	/// update does not block.
	///
	/// Links from `onOpenURL` carry ``DeepLinkContext/openedURL(_:sourceApplication:sceneID:)``
	/// (``DeepLinkContext/Source/customScheme``, or ``DeepLinkContext/Source/unknown``
	/// for unverified `http(s)`), and browsing-web activities carry ``DeepLinkContext/Source/universalLink``.
	/// SwiftUI does not expose the source application or scene identifier here;
	/// use `onDeepLink(_:sceneID:)` in multi-window apps.
	///
	/// ## Ordering
	///
	/// Route-execution order is **best-effort**. Each URL the view receives is dispatched
	/// to its own unstructured `Task`, so URLs that arrive in quick succession may have
	/// their coordinator runs interleaved and their side effects reordered relative to
	/// arrival order. If strict ordering matters — for example when URLs mutate a
	/// navigation stack whose state depends on previous URLs — drive the coordinator
	/// from a serial queue or actor above the view layer instead of relying on this
	/// modifier.
	///
	/// ## Example
	///
	/// ```swift
	/// @main
	/// struct MyApp: App {
	///     @State private var coordinator: DeepLinkCoordinator<AppRoute> = …
	///
	///     var body: some Scene {
	///         WindowGroup {
	///             ContentView()
	///                 .onDeepLink(coordinator)
	///         }
	///     }
	/// }
	/// ```
	///
	/// - Parameter coordinator: The coordinator that processes incoming URLs.
	/// - Returns: A view that forwards custom-scheme and Universal Link URLs to the coordinator.
	func onDeepLink(
		_ coordinator: DeepLinkCoordinator<some DeepLinkRoute>,
	) -> some View {
		modifier(OnDeepLinkModifier(coordinator: coordinator, sceneID: nil))
	}

	/// Routes incoming deep links to a coordinator, tagging them with the
	/// identifier of the scene this view belongs to.
	///
	/// SwiftUI does not expose a scene identifier, so the app supplies one,
	/// typically a UUID kept in `@SceneStorage` so each window keeps its own
	/// across launches. Links carry it as ``DeepLinkContext/sceneID``, so a
	/// ``SceneRoutingHandler`` can send each link to the window it arrived in.
	/// An empty identifier is treated as absent.
	///
	/// ```swift
	/// struct WindowRoot: View {
	///     @SceneStorage("deepLinkSceneID") private var sceneID = ""
	///     let coordinator: DeepLinkCoordinator<AppRoute>
	///     let router: SceneRoutingHandler<AppRoute>
	///     @State private var navigator = Navigator()
	///
	///     var body: some View {
	///         ContentView(navigator: navigator)
	///             .onDeepLink(coordinator, sceneID: sceneID)
	///             .onAppear {
	///                 if sceneID.isEmpty { sceneID = UUID().uuidString }
	///                 router.register(navigator, forScene: sceneID)
	///             }
	///             .onDisappear { router.unregister(scene: sceneID) }
	///     }
	/// }
	/// ```
	///
	/// - Parameters:
	///   - coordinator: The coordinator that processes incoming URLs.
	///   - sceneID: The identifier of this view's scene.
	/// - Returns: A view that forwards custom-scheme and Universal Link URLs to the coordinator.
	func onDeepLink(
		_ coordinator: DeepLinkCoordinator<some DeepLinkRoute>,
		sceneID: String?,
	) -> some View {
		modifier(OnDeepLinkModifier(coordinator: coordinator, sceneID: DeepLinkSceneIdentifier.normalized(sceneID)))
	}

	/// Routes incoming deep links and Universal Links to a coordinator that may not yet exist.
	///
	/// Identical to ``onDeepLink(_:)-9wh3a`` but accepts an optional coordinator and no-ops
	/// while the coordinator is `nil`. Use this overload when the coordinator is built
	/// asynchronously (for example inside `.task { … }`) and stored in `@State` as an
	/// optional, so callers don't need to wrap the modifier in their own conditional.
	///
	/// ## Example
	///
	/// ```swift
	/// struct RootView: View {
	///     @State private var coordinator: DeepLinkCoordinator<AppRoute>?
	///
	///     var body: some View {
	///         ContentView()
	///             .onDeepLink(coordinator)
	///             .task { coordinator = await buildCoordinator() }
	///     }
	/// }
	/// ```
	///
	/// - Parameter coordinator: The coordinator that processes incoming URLs, or `nil` to skip subscription.
	/// - Returns: A view that forwards custom-scheme and Universal Link URLs to the coordinator when present.
	func onDeepLink(
		_ coordinator: DeepLinkCoordinator<some DeepLinkRoute>?,
	) -> some View {
		modifier(OptionalOnDeepLinkModifier(coordinator: coordinator, sceneID: nil))
	}

	/// Routes incoming deep links, tagged with this view's scene identifier, to
	/// a coordinator that may not yet exist; no-ops while it is `nil`.
	///
	/// - Parameters:
	///   - coordinator: The coordinator that processes incoming URLs, or `nil` to skip subscription.
	///   - sceneID: The identifier of this view's scene.
	/// - Returns: A view that forwards URLs to the coordinator when present.
	func onDeepLink(
		_ coordinator: DeepLinkCoordinator<some DeepLinkRoute>?,
		sceneID: String?,
	) -> some View {
		modifier(OptionalOnDeepLinkModifier(coordinator: coordinator, sceneID: DeepLinkSceneIdentifier.normalized(sceneID)))
	}
}

enum DeepLinkSceneIdentifier {
	static func normalized(_ sceneID: String?) -> String? {
		sceneID.flatMap { $0.isEmpty ? nil : $0 }
	}

	static func openedURLContext(for url: URL, sceneID: String?) -> DeepLinkContext {
		.openedURL(url, sceneID: normalized(sceneID))
	}
}

private struct OnDeepLinkModifier<Route: DeepLinkRoute>: ViewModifier {
	let coordinator: DeepLinkCoordinator<Route>
	let sceneID: String?

	func body(content: Content) -> some View {
		content
			.onOpenURL { url in
				Task { await coordinator.handle(url: url, context: DeepLinkSceneIdentifier.openedURLContext(for: url, sceneID: sceneID)) }
			}
			.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
				Task { await coordinator.handle(activity: activity, sceneID: sceneID) }
			}
	}
}

private struct OptionalOnDeepLinkModifier<Route: DeepLinkRoute>: ViewModifier {
	let coordinator: DeepLinkCoordinator<Route>?
	let sceneID: String?

	func body(content: Content) -> some View {
		if let coordinator {
			content.modifier(OnDeepLinkModifier(coordinator: coordinator, sceneID: sceneID))
		} else {
			content
		}
	}
}

#endif
