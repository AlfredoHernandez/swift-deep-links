//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Identifies one pass of a link through ``DeepLinkCoordinator``, so
/// middleware can match ``DeepLinkMiddleware/didFinish(_:outcome:)`` with the
/// `intercept` call it follows even when identical links run concurrently.
enum DeepLinkRun {
	@TaskLocal static var id: UUID?

	/// The link as it entered the chain in this pass, before any middleware
	/// rewrote it (for example stripped its signature).
	@TaskLocal static var arrival: DeepLinkRequest?
}

/// What a tracked pass through the middleware chain produced.
struct MiddlewareRun: Sendable {
	var result: Result<DeepLinkRequest?, any Error>
	var visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)] = []
	var wasDeferred = false

	func finish(with outcome: DeepLinkOutcome) async {
		for visit in visited.reversed() {
			await visit.middleware.didFinish(visit.request, outcome: outcome)
		}
	}
}
