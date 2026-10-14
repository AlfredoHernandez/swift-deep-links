//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os.log

/// Default analytics provider that logs events to system logs.
///
/// This basic implementation of `AnalyticsProvider` logs all analytics events
/// to system logs using `os.log`. It's ideal for development, debugging, and cases
/// where data doesn't need to be sent to external analytics services.
///
/// ## Features
/// - **Integrated logging**: Uses `os.log` for efficient logging
/// - **Configurable**: Allows customizing the logger
/// - **Thread-safe**: Safe for concurrent use
/// - **No external dependencies**: Doesn't require third-party services
///
/// ## Use Cases
/// - **Development and debugging**: See analytics events in real-time
/// - **Simple applications**: When complex analytics isn't needed
/// - **Prototyping**: To quickly test the deep link system
/// - **Local logging**: For log analysis without external services
///
/// ## Basic Usage Example
/// ```swift
/// // Use with default configuration
/// let analyticsProvider = DefaultAnalyticsProvider()
///
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: analyticsProvider,
///     strategy: .standard
/// )
/// ```
///
/// ## Custom Logger Example
/// ```swift
/// import os.log
///
/// // Create custom logger for your app
/// let customLogger = Logger(subsystem: "com.myapp.analytics", category: "DeepLinks")
///
/// let customProvider = DefaultAnalyticsProvider(logger: customLogger)
///
/// let middleware = AnalyticsMiddleware(
///     analyticsProvider: customProvider,
///     strategy: .detailed
/// )
/// ```
///
/// ## Log Format
/// Events are logged with the following format:
/// ```
/// Analytics: deep_link_opened - url: myApp://product/123, scheme: myApp, host: product, timestamp: 1640995200.0
/// ```
///
/// ## Viewing Logs in Development
/// To view logs in Xcode:
/// 1. Open Xcode console
/// 2. Filter by "DeepLink" or your custom subsystem
/// 3. Run deep links in the simulator
///
/// To view logs on device:
/// ```bash
/// # In terminal, with device connected
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "DeepLink"'
/// ```
///
/// ## Limitations
/// - Logs don't persist indefinitely
/// - No automatic data aggregation
/// - Not suitable for large-scale production analytics
///
/// ## Migration to Production
/// For production, consider implementing a provider that sends data to:
/// - Firebase Analytics
/// - Mixpanel
/// - Your own analytics backend
/// - Logging services like LogRocket or Sentry
///
/// - SeeAlso: ``AnalyticsProvider`` to implement custom providers
/// - SeeAlso: ``AnalyticsMiddleware`` to use this provider
public final class DefaultAnalyticsProvider: AnalyticsProvider {
	private let log: LoggingProvider
	private let privacy: DeepLinkLogPrivacy

	/// Creates a new default analytics provider.
	///
	/// - Parameters:
	///   - logger: The logger to use for registering events. By default uses
	///     a logger with subsystem "swift-deep-links" and category "DefaultAnalyticsProvider".
	///   - privacy: How parameters are logged. Defaults to ``DeepLinkLogPrivacy/redacted``:
	///     values of sensitive parameter names are replaced and embedded URLs redacted.
	///
	/// ## Example
	/// ```swift
	/// // Use default configuration
	/// let provider = DefaultAnalyticsProvider()
	///
	/// // With custom logger
	/// let customLogger = Logger(subsystem: "com.myapp", category: "DeepLinks")
	/// let customProvider = DefaultAnalyticsProvider(logger: customLogger)
	/// ```
	public convenience init(
		logger: Logger = Logger(subsystem: "swift-deep-links", category: "DefaultAnalyticsProvider"),
		privacy: DeepLinkLogPrivacy = .redacted,
	) {
		self.init(privacy: privacy, log: .systemLogger(logger))
	}

	init(privacy: DeepLinkLogPrivacy = .redacted, log: LoggingProvider) {
		self.privacy = privacy
		self.log = log
	}

	/// Logs an analytics event to system logs.
	///
	/// - Parameters:
	///   - event: The name of the event to track
	///   - parameters: The event parameters
	///
	/// ## Output Example
	/// For the "deep_link_opened" event with parameters:
	/// ```
	/// Analytics: deep_link_opened - url: myApp://product/123, scheme: myApp, host: product, timestamp: 1640995200.0
	/// ```
	public func track(_ event: String, parameters: [String: Any]) {
		let parametersString = parameters.map { "\($0.key): \(loggedValue($0.value, named: $0.key))" }.joined(separator: ", ")
		log.log(level: .info, "Analytics: \(event) - \(parametersString)")
	}

	private func loggedValue(_ value: Any, named name: String) -> String {
		if let redactor = privacy.redactor, redactor.isSensitive(parameterName: name) {
			return redactor.placeholder
		}
		return privacy.redactingURLs(in: "\(value)")
	}
}
