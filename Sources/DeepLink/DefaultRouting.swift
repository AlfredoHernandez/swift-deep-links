//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import OSLog

/// The default implementation of `DeepLinkRouting` that tries multiple parsers.
///
/// `DefaultDeepLinkRouting` provides a standard routing implementation that attempts
/// to parse URLs using multiple parsers in sequence. It returns the first successful
/// result and throws an error if no parser can handle the URL.
///
/// ## Usage
///
/// ```swift
/// let userParser = UserDeepLinkParser()
/// let productParser = ProductDeepLinkParser()
/// let routing = DefaultDeepLinkRouting<AppRoute>(parsers: [userParser, productParser])
/// ```
///
/// ## Behavior
///
/// - Tries each parser in the order provided
/// - Returns the first successful result immediately
/// - Logs errors from failed parsers but continues trying
/// - Throws `DeepLinkError.routeNotFound` if no parser succeeds
/// - Validates the URL structure before attempting to parse
///
/// ## Thread Safety
///
/// This struct is `Sendable` by value semantics and can be safely shared
/// across different execution contexts.
///
/// - Parameter Route: The type of route this routing system produces
public struct DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting {
	private let logger = Logger(subsystem: "swift-deep-link", category: "DefaultDeepLinkRouting")
	private let parsers: [any DeepLinkParser<Route>]

	/// Creates a new default deep link routing instance.
	///
	/// - Parameter parsers: An array of parsers to try in sequence
	public init(parsers: [any DeepLinkParser<Route>]) {
		self.parsers = parsers
	}

	/// Routes a URL by trying multiple parsers until one succeeds.
	///
	/// This method attempts to parse the URL using each provided parser in sequence.
	/// It returns the first successful result and throws an error if no parser
	/// can handle the URL.
	///
	/// - Parameter url: The URL to route
	/// - Returns: An array of routes from the first successful parser
	/// - Throws: `DeepLinkError.routeNotFound` if no parser can handle the URL
	public func route(from url: URL) async throws -> [Route] {
		let deepLinkURL = try DeepLinkURL(url: url)

		guard !parsers.isEmpty else {
			logger.error("No parsers available for URL: \(url.absoluteString)")
			throw DeepLinkError.routeNotFound(deepLinkURL.host)
		}

		var lastError: Error?

		for parser in parsers {
			do {
				let routes = try await parser.parse(from: url)
				logger.debug("Parser \(String(describing: type(of: parser))) successfully parsed URL: \(url.absoluteString)")
				return routes
			} catch {
				logger.debug("Parser \(String(describing: type(of: parser))) failed to parse URL: \(url.absoluteString) - Error: \(error.localizedDescription)")
				lastError = error
				continue
			}
		}

		let parsersCount = parsers.count
		if let lastError {
			logger.error("All \(parsersCount) parsers failed for URL: \(url.absoluteString) - Last error: \(lastError.localizedDescription)")
		} else {
			logger.error("All \(parsersCount) parsers failed for URL: \(url.absoluteString)")
		}

		throw DeepLinkError.routeNotFound(deepLinkURL.host)
	}
}
