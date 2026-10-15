//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Runs a link's routes through the handler one after another, pausing
/// `delay` between them, and tallies how each route ended.
struct RouteExecutor<Route: DeepLinkRoute>: Sendable {
	let handler: any DeepLinkHandler<Route>
	let delay: Duration
	let sleep: @Sendable (Duration) async -> Void
	let log: LoggingProvider
	let logPrivacy: DeepLinkLogPrivacy

	func execute(_ routes: [Route], context: DeepLinkContext) async -> RouteExecutionResult {
		var successfulRoutes = 0
		var failedRoutes = 0
		var declinedRoutes = 0
		var errors: [any Error] = []

		for (index, route) in routes.enumerated() {
			let decline = RouteDecline()
			do {
				try await DeepLinkRun.updating({ $0.routeDecline = decline }) {
					try await handler.handle(route, context: context)
				}
				successfulRoutes += 1
			} catch {
				failedRoutes += 1
				declinedRoutes += decline.declined(error) ? 1 : 0
				errors.append(error)
				log.log(level: .error, "Error handling route \(route.id): \(logPrivacy.describe(error))")
			}

			if delay > .zero, index < routes.count - 1 {
				await sleep(delay)
			}
		}

		return RouteExecutionResult(
			successfulRoutes: successfulRoutes,
			failedRoutes: failedRoutes,
			declinedRoutes: declinedRoutes,
			errors: errors,
		)
	}
}

/// How a link's routes ended.
struct RouteExecutionResult {
	let successfulRoutes: Int
	let failedRoutes: Int
	let declinedRoutes: Int
	let errors: [any Error]

	/// ``DeepLinkOutcome/failed(_:)`` when route guards declined every route
	/// before any handler ran, so nothing executed (a signed link's nonce is
	/// released, as when ``ConfirmationMiddleware`` denies it);
	/// ``DeepLinkOutcome/handlerFailed(_:)`` when anything else failed.
	var outcome: DeepLinkOutcome {
		guard let firstError = errors.first else { return .succeeded }
		let nothingExecuted = successfulRoutes == 0 && declinedRoutes == failedRoutes
		return nothingExecuted ? .failed(firstError) : .handlerFailed(firstError)
	}
}
