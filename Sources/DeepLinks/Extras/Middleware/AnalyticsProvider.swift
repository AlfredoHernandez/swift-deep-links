//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for analytics providers.
///
/// This protocol defines the interface that analytics providers must implement
/// to send deep link events to different analytics services.
///
/// ## Included Implementations
/// - `DefaultAnalyticsProvider`: Basic implementation that logs to system logs
///
/// ## Common Custom Implementations
/// - Firebase Analytics
/// - Mixpanel
/// - Amplitude
/// - Custom analytics backend
///
/// ## Basic Implementation Example
/// ```swift
/// struct MyAnalyticsProvider: AnalyticsProvider {
///     func track(_ event: String, parameters: [String: Any]) {
///         // Send to your analytics service
///         MyAnalyticsService.track(event: event, parameters: parameters)
///     }
/// }
/// ```
///
/// ## Firebase Analytics Example
/// ```swift
/// import FirebaseAnalytics
///
/// struct FirebaseAnalyticsProvider: AnalyticsProvider {
///     func track(_ event: String, parameters: [String: Any]) {
///         Analytics.logEvent(event, parameters: parameters)
///     }
/// }
/// ```
///
/// ## Implementation Considerations
/// - The method must be thread-safe and can be called from any thread
/// - Implementations should handle errors internally
/// - For better performance, consider implementing event batching
/// - Ensure compliance with privacy policies in your implementation
///
/// - SeeAlso: ``AnalyticsMiddleware`` to use this protocol
/// - SeeAlso: ``DefaultAnalyticsProvider`` for a basic implementation
public protocol AnalyticsProvider: Sendable {
	/// Sends an analytics event with parameters.
	///
	/// - Parameters:
	///   - event: The name of the event to track (e.g., "deep_link_opened")
	///   - parameters: Dictionary with the event parameters
	func track(_ event: String, parameters: [String: Any])
}
