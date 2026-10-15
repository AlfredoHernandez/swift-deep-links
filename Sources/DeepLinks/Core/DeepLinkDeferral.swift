//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// The middleware that ran before a ReadinessMiddleware queued a link,
/// waiting to hear how the link finally ended.
///
/// It travels with the queued DeepLinkRequest and is settled exactly once:
/// with the drained pass's outcome, or with DeepLinkOutcome/stopped when
/// the queue evicts or resets the link. Settlement runs under the original
/// pass's identifier so middleware can find what it held for the link.
final class DeepLinkDeferral: Sendable {
	private let runID: UUID?

	/// The link as it entered the chain in the pass that queued it, so the
	/// drained pass saves pending links with their signature intact.
	let arrival: DeepLinkRequest?
	private let visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)]
	private let isSettled = OSAllocatedUnfairLock(initialState: false)

	init(runID: UUID?, arrival: DeepLinkRequest?, visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)]) {
		self.runID = runID
		self.arrival = arrival
		self.visited = visited
	}

	func settle(with outcome: DeepLinkOutcome) async {
		let isFirst = isSettled.withLock { settled in
			defer { settled = true }
			return !settled
		}
		guard isFirst else { return }
		await DeepLinkRun.updating({ $0.id = runID }) {
			for visit in visited.reversed() {
				await visit.middleware.didFinish(visit.request, outcome: outcome)
			}
		}
	}

	/// Settles as DeepLinkOutcome/stopped without blocking the caller,
	/// for queues dropping a link from synchronous code.
	func settleDropped() {
		Task { await settle(with: .stopped) }
	}
}
