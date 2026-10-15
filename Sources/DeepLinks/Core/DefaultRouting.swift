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
/// - Throws `DeepLinkError.routeNotFound(url)` when no parsers are configured
/// - Throws `DeepLinkError.parsingFailed(url:underlyingErrors:)` when at
///   least one parser is configured but every parser threw — the errors
///   are collected in order so consumers can introspect them. Nested
///   `DeepLinkError.parsingFailed` thrown by a delegating parser is
///   flattened: its `underlyingErrors` are spliced into the outer
///   collection, so callers never see `parsingFailed(parsingFailed(...))`
/// - Stops at the first ``DeepLinkError/securityViolation(_:)`` or
///   ``DeepLinkError/blockedURL(_:)`` a parser throws (also when nested in a
///   delegating parser's `parsingFailed`) and rethrows it, so a laxer later
///   parser cannot accept a link a stricter one rejected
/// - Validates the URL structure before attempting to parse
///
/// ## Thread Safety
///
/// This struct is `Sendable` by value semantics and can be safely shared
/// across different execution contexts.
///
/// - Parameter Route: The type of route this routing system produces
public struct DefaultDeepLinkRouting<Route: DeepLinkRoute>: DeepLinkRouting {
	private let log: LoggingProvider
	private let logPrivacy: DeepLinkLogPrivacy
	private let parsers: [any DeepLinkParser<Route>]
	private let duplicateParameterLimits: DeepLinkInputLimits?

	/// Creates a new default deep link routing instance.
	///
	/// - Parameters:
	///   - parsers: An array of parsers to try in sequence
	///   - rejectDuplicateParameters: When `true`, a URL that repeats a query key throws
	///     ``DeepLinkError/securityViolation(_:)`` before any parser runs. Defaults to `false`.
	///   - logPrivacy: How log messages describe URLs and parser errors.
	///     Defaults to ``DeepLinkLogPrivacy/redacted``.
	public init(
		parsers: [any DeepLinkParser<Route>],
		rejectDuplicateParameters: Bool = false,
		logPrivacy: DeepLinkLogPrivacy = .redacted,
	) {
		self.init(
			parsers: parsers,
			rejectDuplicateParameters: rejectDuplicateParameters,
			logPrivacy: logPrivacy,
			log: .systemLogger(Logger(subsystem: "swift-deep-links", category: "DefaultDeepLinkRouting")),
		)
	}

	init(
		parsers: [any DeepLinkParser<Route>],
		rejectDuplicateParameters: Bool = false,
		logPrivacy: DeepLinkLogPrivacy = .redacted,
		log: LoggingProvider,
	) {
		self.parsers = parsers
		duplicateParameterLimits = rejectDuplicateParameters ? DeepLinkInputLimits(rejectDuplicateParameters: true) : nil
		self.logPrivacy = logPrivacy
		self.log = log
	}

	/// Routes a URL by trying multiple parsers until one succeeds.
	///
	/// This method attempts to parse the URL using each provided parser in
	/// sequence. It returns the first successful result, and otherwise
	/// surfaces the errors from the parser chain:
	///
	/// - If no parsers are configured, throws
	///   ``DeepLinkError/routeNotFound(_:)``.
	/// - If a parser throws ``DeepLinkError/securityViolation(_:)`` or
	///   ``DeepLinkError/blockedURL(_:)``, rethrows it without trying the
	///   remaining parsers.
	/// - If at least one parser is configured but every parser threw,
	///   throws ``DeepLinkError/parsingFailed(url:underlyingErrors:)`` with
	///   the collected failures in order.
	///
	/// - Parameter url: The URL to route
	/// - Returns: An array of routes from the first successful parser
	/// - Throws: ``DeepLinkError/routeNotFound(_:)`` when no parsers are
	///   configured, or ``DeepLinkError/parsingFailed(url:underlyingErrors:)``
	///   when all parsers threw.
	public func route(from url: URL) async throws -> [Route] {
		_ = try DeepLinkURL(url: url)
		try duplicateParameterLimits?.validate(url)

		guard !parsers.isEmpty else {
			log.log(level: .error, "No parsers available for URL: \(logPrivacy.describe(url))")
			throw DeepLinkError.routeNotFound(url)
		}

		var underlyingErrors: [any Error & Sendable] = []

		for parser in parsers {
			do {
				let routes = try await parser.parse(from: url)
				log.log(level: .debug, "Parser \(String(describing: type(of: parser))) successfully parsed URL: \(logPrivacy.describe(url))")
				return routes
			} catch let error as DeepLinkError where error.stopsRouting {
				throw error
			} catch {
				log.log(
					level: .debug,
					"Parser \(String(describing: type(of: parser))) failed to parse URL: \(logPrivacy.describe(url)) - Error: \(logPrivacy.describe(error))",
				)
				if let deepLinkError = error as? DeepLinkError,
				   case let .parsingFailed(_, nestedErrors) = deepLinkError
				{
					if let securityError = nestedErrors.lazy.compactMap({ $0 as? DeepLinkError }).first(where: \.stopsRouting) {
						throw securityError
					}
					underlyingErrors.append(contentsOf: nestedErrors)
				} else {
					underlyingErrors.append(error)
				}
				continue
			}
		}

		let parsersCount = parsers.count
		if let last = underlyingErrors.last {
			log.log(level: .error, "All \(parsersCount) parsers failed for URL: \(logPrivacy.describe(url)) - Last error: \(logPrivacy.describe(last))")
		} else {
			log.log(level: .error, "All \(parsersCount) parsers failed for URL: \(logPrivacy.describe(url))")
		}

		throw DeepLinkError.parsingFailed(url: url, underlyingErrors: underlyingErrors)
	}
}

// MARK: - Routing-Stopping Errors

private extension DeepLinkError {
	var stopsRouting: Bool {
		switch self {
		case .securityViolation, .blockedURL: true
		default: false
		}
	}
}
