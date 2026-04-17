//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// An analytics provider that collects all tracked events for inspection.
///
/// `CollectingAnalyticsProvider` records every analytics event sent to it,
/// converting all parameter values to strings for safe storage. Thread-safe through lock protection.
///
/// ## Overview
///
/// Create an analytics provider, attach it to your middleware, and verify tracked events:
///
///     let analytics = CollectingAnalyticsProvider()
///     let middleware = AnalyticsMiddleware(analyticsProvider: analytics)
///     // ... process deep links ...
///
///     #expect(analytics.trackedEvents.first?.name == "deep_link_opened")
///
/// ## Verifying Event Parameters
///
/// Inspect both event names and their parameters:
///
///     let analytics = CollectingAnalyticsProvider()
///     let middleware = AnalyticsMiddleware(analyticsProvider: analytics)
///     await coordinator.handle(url: someURL)
///
///     if let event = analytics.trackedEvents.first {
///         #expect(event.name == "deep_link_opened")
///         #expect(event.parameters["source"] == "push_notification")
///     }
///
/// - Note: All parameter values are converted to strings for consistent, sendable storage.
/// - Complexity: O(n) where n is the number of parameters being converted to strings.
/// - SeeAlso: `AnalyticsProvider`
public final class CollectingAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
	/// A captured analytics event with stringified parameters.
	///
	/// This structure stores both the event name and all its parameters
	/// as strings for consistent, thread-safe storage.
	public struct TrackedEvent: Sendable {
		/// The event name (e.g., `"deep_link_opened"`).
		///
		/// This is the identifier for the analytics event type.
		public let name: String

		/// The event parameters as string key-value pairs.
		///
		/// All parameter values from the original event have been converted
		/// to their string representations.
		public let parameters: [String: String]
	}

	private let state = OSAllocatedUnfairLock(initialState: [TrackedEvent]())

	/// Initializes a new collecting analytics provider with no recorded events.
	public init() {}

	/// All tracked events, in order.
	///
	/// Access this property to assert which analytics events were sent during your test.
	/// The events are stored in the order they were tracked, with all parameter
	/// values converted to strings.
	public var trackedEvents: [TrackedEvent] {
		state.withLock { $0 }
	}

	public func track(_ event: String, parameters: [String: Any]) {
		let sendableParams = parameters.compactMapValues { "\($0)" }
		let tracked = TrackedEvent(name: event, parameters: sendableParams)
		state.withLock { $0.append(tracked) }
	}
}
