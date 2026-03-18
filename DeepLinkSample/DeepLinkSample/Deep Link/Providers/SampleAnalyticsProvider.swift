//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

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
/// - Thread-safe operations
///
/// ## Usage:
/// ```swift
/// let analyticsProvider = SampleAnalyticsProvider()
/// await analyticsProvider.track("deep_link_opened", parameters: ["url": url.absoluteString])
///
/// // For testing
/// let events = analyticsProvider.getTrackedEvents()
/// ```
final class SampleAnalyticsProvider: AnalyticsProvider, @unchecked Sendable {
	// MARK: - Private Properties

	private var trackedEvents: [(event: String, parameters: [String: Any])] = []
	private let queue = DispatchQueue(label: "com.sample.analytics", attributes: .concurrent)

	// MARK: - Public Interface

	/// Tracks an analytics event with optional parameters.
	///
	/// This method simulates sending analytics data to a remote service.
	/// In a real application, this would make network calls to your analytics service.
	///
	/// - Parameters:
	///   - event: The name of the event to track
	///   - parameters: Optional parameters associated with the event
	func track(_ event: String, parameters: [String: Any]) async {
		// Simulate async analytics tracking
		try? await Task.sleep(nanoseconds: 5_000_000) // 5ms delay

		await withCheckedContinuation { continuation in
			queue.async(flags: .barrier) {
				self.trackedEvents.append((event: event, parameters: parameters))
				print("📊 Analytics: \(event) - \(parameters)")
				continuation.resume()
			}
		}
	}

	/// Gets all tracked events for testing/debugging purposes.
	///
	/// This method provides access to the event history for verification
	/// and debugging during development and testing.
	///
	/// - Returns: An array of tracked events with their parameters
	func getTrackedEvents() -> [(event: String, parameters: [String: Any])] {
		queue.sync {
			trackedEvents
		}
	}

	/// Gets tracked events count.
	///
	/// - Returns: The number of events that have been tracked
	func getTrackedEventsCount() -> Int {
		queue.sync {
			trackedEvents.count
		}
	}

	/// Clears all tracked events.
	///
	/// This method is useful for testing scenarios where you need to start
	/// with a clean event history.
	func clearTrackedEvents() {
		queue.async(flags: .barrier) {
			self.trackedEvents.removeAll()
		}
	}

	/// Gets events filtered by event name.
	///
	/// - Parameter eventName: The name of the events to filter by
	/// - Returns: An array of events matching the specified name
	func getEvents(named eventName: String) -> [(event: String, parameters: [String: Any])] {
		queue.sync {
			trackedEvents.filter { $0.event == eventName }
		}
	}
}
