//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import OSLog

/// A delegate implementation that provides comprehensive logging for deep link processing events.
///
/// This delegate logs detailed information about deep link processing lifecycle,
/// making it easier to debug issues and monitor deep link usage in production.
///
/// ## Usage
///
/// ```swift
/// let loggingDelegate = DeepLinkLoggingDelegate<AppRoute>()
/// coordinator.delegate = loggingDelegate
/// ```
///
/// ## Log Levels
///
/// - **Info**: Normal processing events (willProcess, didProcess)
/// - **Error**: Processing failures and errors
/// - **Debug**: Detailed processing information (when debug logging is enabled)
@MainActor
public final class DeepLinkLoggingDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
	private let log: LoggingProvider
	private let privacy: DeepLinkLogPrivacy
	private let enableDebugLogging: Bool

	/// Creates a new logging delegate.
	///
	/// - Parameters:
	///   - enableDebugLogging: Whether to enable detailed debug logging (default: false)
	///   - privacy: How messages describe URLs and errors. Defaults to ``DeepLinkLogPrivacy/redacted``.
	public convenience init(enableDebugLogging: Bool = false, privacy: DeepLinkLogPrivacy = .redacted) {
		self.init(
			enableDebugLogging: enableDebugLogging,
			privacy: privacy,
			log: .systemLogger(Logger(subsystem: "swift-deep-links", category: "DeepLinkLoggingDelegate")),
		)
	}

	init(enableDebugLogging: Bool = false, privacy: DeepLinkLogPrivacy = .redacted, log: LoggingProvider) {
		self.enableDebugLogging = enableDebugLogging
		self.privacy = privacy
		self.log = log
	}

	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		willProcess url: URL,
	) {
		log.log(level: .info, "Starting deep link processing: \(privacy.describe(url))")

		if enableDebugLogging {
			let loggedURL = privacy.redact(url)
			log.log(
				level: .debug,
				"Deep link details - Scheme: \(loggedURL.scheme ?? "nil"), Host: \(loggedURL.host() ?? "nil"), Path: \(loggedURL.path), Query: \(loggedURL.query ?? "nil")",
			)
		}
	}

	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didProcess url: URL,
		result: DeepLinkResult<Route>,
	) {
		if result.wasSuccessful {
			log.log(level: .info, "Deep link processed successfully: \(privacy.describe(url))")

			if enableDebugLogging {
				log.log(level: .debug, "Processing details - Execution time: \(String(format: "%.3f", result.executionTime))s")
			}
		} else {
			log.log(level: .error, "Deep link processing failed: \(privacy.describe(url))")

			if !result.errors.isEmpty {
				for (index, error) in result.errors.enumerated() {
					log.log(level: .error, "Error \(index + 1): \(privacy.describe(error))")
				}
			}

			if enableDebugLogging {
				log.log(
					level: .debug,
					"Failure details - Successful: \(result.successfulRoutes), Failed: \(result.failedRoutes), Execution time: \(String(format: "%.3f", result.executionTime))s",
				)
			}
		}

		if result.wasStoppedByMiddleware {
			log.log(level: .info, "Deep link processing stopped by middleware: \(privacy.describe(url))")
		}
	}

	public func coordinator(
		_: DeepLinkCoordinator<Route>,
		didFailProcessing url: URL,
		error: Error,
	) {
		log.log(level: .error, "Deep link processing failed with critical error: \(privacy.describe(url))")
		log.log(level: .error, "Critical error: \(privacy.describe(error))")

		if enableDebugLogging {
			let nsError = error as NSError
			let userInfo = privacy.redactor == nil ? "\(nsError.userInfo)" : "<redacted>"
			log.log(level: .debug, "Error details - Domain: \(nsError.domain), Code: \(nsError.code), UserInfo: \(userInfo)")
		}
	}
}
