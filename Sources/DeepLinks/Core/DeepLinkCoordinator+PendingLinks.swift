//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

public extension DeepLinkCoordinator {
	/// Runs every link pending in `store` through the whole pipeline again.
	///
	/// Call it once the condition that blocked the links is resolved, typically
	/// right after sign-in. Each link restarts at the first middleware, so
	/// security, rate limiting and authentication are evaluated again: a link
	/// that is still unauthorized fails with
	/// ``DeepLinkError/unauthorizedAccess(_:)`` and, when the authentication
	/// middleware is configured with the same store, is saved again. Delegate
	/// notifications fire for each link as for ``handle(url:)``.
	///
	/// ## Example
	///
	/// ```swift
	/// let pendingLinks = InMemoryPendingLinkStore()
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(parser)
	///     .handler(handler)
	///     .middleware(.authentication(provider: auth, protectedHosts: ["account"], pendingLinks: pendingLinks))
	///     .build()
	///
	/// func didSignIn() async {
	///     await coordinator.resumePendingLinks(from: pendingLinks)
	/// }
	/// ```
	///
	/// - Parameter store: The store whose links to resume; it is emptied first.
	/// - Returns: One result per resumed link, oldest first.
	@discardableResult
	func resumePendingLinks(from store: any PendingLinkStore) async -> [DeepLinkResult<Route>] {
		var results: [DeepLinkResult<Route>] = []
		for url in await store.takeAll() {
			await results.append(handle(url: url))
		}
		return results
	}
}
