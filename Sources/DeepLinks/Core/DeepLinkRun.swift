//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// Identifies one pass of a link through ``DeepLinkCoordinator``, so
/// middleware can match ``DeepLinkMiddleware/didFinish(_:outcome:)`` with the
/// `intercept` call it follows even when identical links run concurrently.
enum DeepLinkRun {
	@TaskLocal static var id: UUID?

	/// The link as it entered the chain in this pass, before any middleware
	/// rewrote it (for example stripped its signature).
	@TaskLocal static var arrival: DeepLinkRequest?

	/// The URL the router and handlers received in this pass, after every
	/// middleware (signature parameters already stripped).
	@TaskLocal static var routedURL: URL?

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
				try await $routedURL.withValue(nil) {
					try await body()
				}
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

/// The middleware that ran before a ``ReadinessMiddleware`` queued a link,
/// waiting to hear how the link finally ended.
///
/// It travels with the queued ``DeepLinkRequest`` and is settled exactly once:
/// with the drained pass's outcome, or with ``DeepLinkOutcome/stopped`` when
/// the queue evicts or resets the link. Settlement runs under the original
/// pass's identifier so middleware can find what it held for the link.
final class DeepLinkDeferral: Sendable {
	private let runID: UUID?
	private let visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)]
	private let isSettled = OSAllocatedUnfairLock(initialState: false)

	init(runID: UUID?, visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)]) {
		self.runID = runID
		self.visited = visited
	}

	func settle(with outcome: DeepLinkOutcome) async {
		let isFirst = isSettled.withLock { settled in
			defer { settled = true }
			return !settled
		}
		guard isFirst else { return }
		await DeepLinkRun.$id.withValue(runID) {
			for visit in visited.reversed() {
				await visit.middleware.didFinish(visit.request, outcome: outcome)
			}
		}
	}

	/// Settles as ``DeepLinkOutcome/stopped`` without blocking the caller,
	/// for queues dropping a link from synchronous code.
	func settleDropped() {
		Task { await settle(with: .stopped) }
	}
}
