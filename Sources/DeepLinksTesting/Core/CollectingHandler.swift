//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// A handler that collects all routes it receives for later inspection.
///
/// Use this to verify which routes were handled and in what order.
///
/// ```swift
/// let handler = CollectingHandler<AppRoute>()
/// let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
/// await coordinator.handle(url: someURL)
///
/// #expect(handler.handledRoutes == [.profile(userID: "42")])
/// ```
public final class CollectingHandler<Route: DeepLinkRoute>: DeepLinkHandler, @unchecked Sendable {
	private let state = OSAllocatedUnfairLock(initialState: [Route]())

	public init() {}

	/// All routes that have been handled, in order.
	public var handledRoutes: [Route] {
		state.withLock { $0 }
	}

	public func handle(_ route: Route) async throws {
		state.withLock { $0.append(route) }
	}
}
