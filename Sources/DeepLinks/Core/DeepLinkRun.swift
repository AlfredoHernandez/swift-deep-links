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

	/// Runs `body` as a standalone call, not part of the enclosing
	/// coordinator pass, so middleware called from a handler (for example
	/// ``DeepLinkMiddlewareCoordinator/process(_:)-(DeepLinkRequest)``) cannot
	/// settle or overwrite the outer link's state.
	static func outside<Output>(
		isolation _: isolated (any Actor)? = #isolation,
		_ body: () async throws -> Output,
	) async rethrows -> Output {
		try await $id.withValue(nil) {
			try await $arrival.withValue(nil) {
				try await body()
			}
		}
	}
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
