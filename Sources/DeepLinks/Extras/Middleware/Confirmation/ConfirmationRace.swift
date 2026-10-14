//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

enum ConfirmationRace {
	/// Races `ask` against `timeout` in unstructured tasks, so the first
	/// outcome returns even when `ask` ignores cancellation. A timeout, or
	/// cancelling the calling task, decides `false`; the loser is cancelled.
	static func decide(
		timeout: Duration?,
		sleep: @Sendable @escaping (Duration) async throws -> Void,
		ask: @Sendable @escaping () async -> Bool,
	) async -> Bool {
		guard let timeout else { return await ask() }

		let decision = FirstDecision()
		let promptTask = Task { await decision.resolve(ask()) }
		let timerTask = Task {
			try? await sleep(timeout)
			decision.resolve(false)
		}
		defer {
			promptTask.cancel()
			timerTask.cancel()
		}
		return await withTaskCancellationHandler {
			await decision.value
		} onCancel: {
			decision.resolve(false)
		}
	}
}

/// A decision that the first of several racers settles; later answers are ignored.
final class FirstDecision: Sendable {
	private struct State {
		var decision: Bool?
		var waiter: CheckedContinuation<Bool, Never>?
	}

	private let state = OSAllocatedUnfairLock(initialState: State())

	var value: Bool {
		get async {
			await withCheckedContinuation { continuation in
				let settled = state.withLock { state -> Bool? in
					if state.decision == nil {
						state.waiter = continuation
					}
					return state.decision
				}
				if let settled {
					continuation.resume(returning: settled)
				}
			}
		}
	}

	func resolve(_ decision: Bool) {
		let waiter = state.withLock { state -> CheckedContinuation<Bool, Never>? in
			guard state.decision == nil else { return nil }
			state.decision = decision
			defer { state.waiter = nil }
			return state.waiter
		}
		waiter?.resume(returning: decision)
	}
}
