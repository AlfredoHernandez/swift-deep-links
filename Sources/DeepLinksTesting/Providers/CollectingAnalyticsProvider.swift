//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// An analytics provider that collects all tracked events for inspection.
///
/// ```swift
/// let analytics = CollectingAnalyticsProvider()
/// let middleware = AnalyticsMiddleware(analyticsProvider: analytics)
/// // ... process deep links ...
///
/// #expect(analytics.trackedEvents.first?.name == "deep_link_opened")
/// ```
public final class CollectingAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
	/// A captured analytics event.
	public struct TrackedEvent: Sendable {
		/// The event name (e.g., `"deep_link_opened"`).
		public let name: String

		/// The event parameters as string key-value pairs.
		public let parameters: [String: String]
	}

	private let state = OSAllocatedUnfairLock(initialState: [TrackedEvent]())

	public init() {}

	/// All tracked events, in order.
	public var trackedEvents: [TrackedEvent] {
		state.withLock { $0 }
	}

	public func track(_ event: String, parameters: [String: Any]) {
		let sendableParams = parameters.compactMapValues { "\($0)" }
		let tracked = TrackedEvent(name: event, parameters: sendableParams)
		state.withLock { $0.append(tracked) }
	}
}
