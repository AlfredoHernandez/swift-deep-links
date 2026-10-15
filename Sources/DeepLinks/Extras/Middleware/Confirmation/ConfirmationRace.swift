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

	/// Like ``decide(timeout:sleep:ask:)``, but `ask` runs only in its turn
	/// at `gate`, and the timeout counts from now, so it covers the wait for
	/// earlier turns. The gate is released as soon as the decision is made,
	/// even when `ask` ignores cancellation.
	///
	/// - Returns: The decision, or `nil` when the calling task was cancelled before `ask` ran.
	static func decide(
		timeout: Duration?,
		sleep: @Sendable @escaping (Duration) async throws -> Void,
		inTurnOf gate: AsyncSerialGate,
		ask: @Sendable @escaping () async -> Bool,
	) async -> Bool? {
		let decision = FirstDecision()
		let wasAsked = OSAllocatedUnfairLock(initialState: false)
		let turnTask = Task {
			let turn = try? await gate.run {
				wasAsked.withLock { $0 = true }
				let askTask = Task { await decision.resolve(ask()) }
				defer { askTask.cancel() }
				return await decision.value
			}
			if turn == nil {
				decision.resolve(false)
			}
		}
		let timerTask = timeout.map { timeout in
			Task {
				try? await sleep(timeout)
				decision.resolve(false)
			}
		}
		defer {
			turnTask.cancel()
			timerTask?.cancel()
		}
		let approved = await withTaskCancellationHandler {
			await decision.value
		} onCancel: {
			decision.resolve(false)
		}
		let isUnasked = !wasAsked.withLock { $0 }
		return Task.isCancelled && isUnasked ? nil : approved
	}
}

/// A decision that the first of several racers settles; later answers are ignored.
final class FirstDecision: Sendable {
	private struct State {
		var decision: Bool?
		var waiters: [CheckedContinuation<Bool, Never>] = []
	}

	private let state = OSAllocatedUnfairLock(initialState: State())

	var value: Bool {
		get async {
			await withCheckedContinuation { continuation in
				let settled = state.withLock { state -> Bool? in
					if state.decision == nil {
						state.waiters.append(continuation)
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
		let waiters = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
			guard state.decision == nil else { return [] }
			state.decision = decision
			defer { state.waiters = [] }
			return state.waiters
		}
		waiters.forEach { $0.resume(returning: decision) }
	}
}
