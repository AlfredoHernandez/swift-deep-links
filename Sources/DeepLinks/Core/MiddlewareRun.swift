//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

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
