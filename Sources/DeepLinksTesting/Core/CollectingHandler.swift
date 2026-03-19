//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// A handler that collects all routes it receives for later inspection.
///
/// `CollectingHandler` records every route passed to it, allowing tests to verify
/// which routes were handled and in what order. Thread-safe through lock protection.
///
/// ## Overview
///
/// Create a `CollectingHandler`, use it with your deep link coordinator, and inspect the results:
///
///     let handler = CollectingHandler<AppRoute>()
///     let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
///     await coordinator.handle(url: someURL)
///
///     #expect(handler.handledRoutes == [.profile(userID: "42")])
///
/// ## Verifying Route Order
///
/// Ensure routes are handled in the expected sequence:
///
///     let handler = CollectingHandler<AppRoute>()
///     // ... handle multiple URLs ...
///
///     #expect(handler.handledRoutes.count == 3)
///     #expect(handler.handledRoutes[0] == .home)
///     #expect(handler.handledRoutes[1] == .search(query: "test"))
///
/// - Note: This handler performs no actual route processing; it only records routes.
/// - Complexity: O(1) for recording each route.
/// - SeeAlso: `CollectingMiddleware`, `CollectingDelegate`
public final class CollectingHandler<Route: DeepLinkRoute>: DeepLinkHandler, @unchecked Sendable {
	private let state = OSAllocatedUnfairLock(initialState: [Route]())

	/// Initializes a new collecting handler with no recorded routes.
	public init() {}

	/// All routes that have been handled, in order.
	///
	/// Access this property to assert which routes were processed during your test.
	/// The routes are stored in the order they were received.
	public var handledRoutes: [Route] {
		state.withLock { $0 }
	}

	public func handle(_ route: Route) async throws {
		state.withLock { $0.append(route) }
	}
}
