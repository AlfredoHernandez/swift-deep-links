//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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
///
/// A link queued again by a later gate after draining carries a new deferral
/// chained to the earlier one, so settling the last gate's deferral also
/// settles every middleware the link passed before the earlier gates.
final class DeepLinkDeferral: Sendable {
	private let runID: UUID?

	/// The link as it entered the chain in the pass that queued it, so the
	/// drained pass saves pending links with their signature intact.
	let arrival: DeepLinkRequest?
	private let visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)]
	private let previous: DeepLinkDeferral?
	private let isSettled = OSAllocatedUnfairLock(initialState: false)

	init(
		runID: UUID?,
		arrival: DeepLinkRequest?,
		visited: [(middleware: any DeepLinkMiddleware, request: DeepLinkRequest)],
		previous: DeepLinkDeferral? = nil,
	) {
		self.runID = runID
		self.arrival = arrival
		self.visited = visited
		self.previous = previous
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
		await previous?.settle(with: outcome)
	}

	/// Settles as DeepLinkOutcome/stopped without blocking the caller,
	/// for queues dropping a link from synchronous code.
	func settleDropped() {
		Task { await settle(with: .stopped) }
	}
}
