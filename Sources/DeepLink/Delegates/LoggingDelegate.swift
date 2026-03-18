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
/// let loggingDelegate = DeepLinkLoggingDelegate()
/// coordinator.delegate = loggingDelegate
/// ```
///
/// ## Log Levels
///
/// - **Info**: Normal processing events (willProcess, didProcess)
/// - **Error**: Processing failures and errors
/// - **Debug**: Detailed processing information (when debug logging is enabled)
public final class DeepLinkLoggingDelegate: DeepLinkCoordinatorDelegate, @unchecked Sendable {
	private let logger = Logger(subsystem: "swift-deep-link", category: "DeepLinkLoggingDelegate")
	private let enableDebugLogging: Bool

	/// Creates a new logging delegate.
	///
	/// - Parameter enableDebugLogging: Whether to enable detailed debug logging (default: false)
	public init(enableDebugLogging: Bool = false) {
		self.enableDebugLogging = enableDebugLogging
	}

	public func coordinator(
		_: AnyObject,
		willProcess url: URL,
	) {
		logger.info("Starting deep link processing: \(url.absoluteString)")

		if enableDebugLogging {
			logger.debug("Deep link details - Scheme: \(url.scheme ?? "nil"), Host: \(url.host() ?? "nil"), Path: \(url.path), Query: \(url.query ?? "nil")")
		}
	}

	public func coordinator(
		_: AnyObject,
		didProcess url: URL,
		result: DeepLinkResultProtocol,
	) {
		if result.wasSuccessful {
			logger.info("Deep link processed successfully: \(url.absoluteString)")

			if enableDebugLogging {
				logger.debug("Processing details - Execution time: \(String(format: "%.3f", result.executionTime))s")
			}
		} else {
			logger.error("Deep link processing failed: \(url.absoluteString)")

			if !result.errors.isEmpty {
				for (index, error) in result.errors.enumerated() {
					logger.error("Error \(index + 1): \(error.localizedDescription)")
				}
			}

			if enableDebugLogging {
				logger
					.debug(
						"Failure details - Successful: \(result.successfulRoutes), Failed: \(result.failedRoutes), Execution time: \(String(format: "%.3f", result.executionTime))s",
					)
			}
		}

		if result.wasStoppedByMiddleware {
			logger.info("Deep link processing stopped by middleware: \(url.absoluteString)")
		}
	}

	public func coordinator(
		_: AnyObject,
		didFailProcessing url: URL,
		error: Error,
	) {
		logger.error("Deep link processing failed with critical error: \(url.absoluteString)")
		logger.error("Critical error: \(error.localizedDescription)")

		if enableDebugLogging {
			let nsError = error as NSError
			logger.debug("Error details - Domain: \(nsError.domain), Code: \(nsError.code), UserInfo: \(nsError.userInfo)")
		}
	}
}
