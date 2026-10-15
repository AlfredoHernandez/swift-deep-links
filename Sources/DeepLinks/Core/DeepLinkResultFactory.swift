//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Builds the ``DeepLinkResult`` for each way a link can end, timing it from
/// `startTime`.
enum DeepLinkResultFactory<Route: DeepLinkRoute> {
	static func failed(url: URL, error: any Error, startTime: Date) -> DeepLinkResult<Route> {
		DeepLinkResult(
			originalURL: url,
			processedURL: nil,
			routes: [],
			executionTime: Date().timeIntervalSince(startTime),
			errors: [error],
			successfulRoutes: 0,
			failedRoutes: 0,
		)
	}

	static func stopped(url: URL, startTime: Date) -> DeepLinkResult<Route> {
		DeepLinkResult(
			originalURL: url,
			processedURL: nil,
			routes: [],
			executionTime: Date().timeIntervalSince(startTime),
			errors: [],
			successfulRoutes: 0,
			failedRoutes: 0,
		)
	}

	static func completed(
		originalURL: URL,
		processedURL: URL,
		routes: [Route],
		execution: RouteExecutionResult,
		startTime: Date,
	) -> DeepLinkResult<Route> {
		DeepLinkResult(
			originalURL: originalURL,
			processedURL: processedURL,
			routes: routes,
			executionTime: Date().timeIntervalSince(startTime),
			errors: execution.errors,
			successfulRoutes: execution.successfulRoutes,
			failedRoutes: execution.failedRoutes,
		)
	}
}
