//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import os

/// Sample analytics provider for demonstration purposes.
///
/// This provider simulates analytics tracking for deep link events.
/// In a real application, this would integrate with your analytics service
/// (such as Firebase Analytics, Mixpanel, or Amplitude) to track user behavior
/// and deep link usage patterns.
///
/// ## Features:
/// - Event tracking with parameters
/// - Event history storage for testing
/// - Debug logging of tracked events
/// - Thread-safe operations via `OSAllocatedUnfairLock`
///
/// ## Usage:
/// ```swift
/// let analyticsProvider = SampleAnalyticsProvider()
/// analyticsProvider.track("deep_link_opened", parameters: ["url": url.absoluteString])
///
/// // For testing
/// let events = analyticsProvider.getTrackedEvents()
/// ```
final class SampleAnalyticsProvider: AnalyticsProvider, Sendable {
	// MARK: - Private Properties

	private let state = OSAllocatedUnfairLock<[(event: String, parameters: [String: Any])]>(uncheckedState: [])

	// MARK: - Public Interface

	/// Tracks an analytics event with optional parameters.
	///
	/// - Parameters:
	///   - event: The name of the event to track
	///   - parameters: Optional parameters associated with the event
	func track(_ event: String, parameters: [String: Any]) {
		state.withLockUnchecked { $0.append((event: event, parameters: parameters)) }
		print("Analytics: \(event) - \(parameters)")
	}

	/// Gets all tracked events for testing/debugging purposes.
	///
	/// - Returns: An array of tracked events with their parameters
	func getTrackedEvents() -> [(event: String, parameters: [String: Any])] {
		state.withLockUnchecked { $0 }
	}

	/// Gets tracked events count.
	///
	/// - Returns: The number of events that have been tracked
	func getTrackedEventsCount() -> Int {
		state.withLockUnchecked(\.count)
	}

	/// Clears all tracked events.
	func clearTrackedEvents() {
		state.withLockUnchecked { $0.removeAll() }
	}

	/// Gets events filtered by event name.
	///
	/// - Parameter eventName: The name of the events to filter by
	/// - Returns: An array of events matching the specified name
	func getEvents(named eventName: String) -> [(event: String, parameters: [String: Any])] {
		state.withLockUnchecked { $0.filter { $0.event == eventName } }
	}
}
