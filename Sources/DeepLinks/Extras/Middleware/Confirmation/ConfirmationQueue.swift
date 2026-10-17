//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// Shows confirmation prompts one at a time, in arrival order, and admits at
/// most `maxPendingPrompts` links waiting or prompting at once, so a burst of
/// links can neither stack dialogs nor queue prompts the user has to dismiss
/// one by one. Shared by ``ConfirmationMiddleware`` and ``ConfirmingHandler``.
final class ConfirmationQueue: Sendable {
	enum Decision: Equatable {
		case approved
		case denied
		/// The caller's task was cancelled before its prompt was shown.
		case cancelledBeforePrompt
		/// `maxPendingPrompts` links were already waiting or prompting.
		case overCapacity
	}

	let maxPendingPrompts: Int
	private let timeout: Duration?
	private let sleep: @Sendable (Duration) async throws -> Void
	private let gate = AsyncSerialGate()
	private let pendingPrompts = OSAllocatedUnfairLock(initialState: 0)

	init(timeout: Duration?, maxPendingPrompts: Int, sleep: @Sendable @escaping (Duration) async throws -> Void) {
		self.timeout = timeout
		self.maxPendingPrompts = max(1, maxPendingPrompts)
		self.sleep = sleep
	}

	/// Asks in turn; the timeout counts from now, so it covers the wait for earlier prompts.
	func decide(_ ask: @Sendable @escaping () async -> Bool) async -> Decision {
		guard reservePendingSlot() else { return .overCapacity }
		defer { releasePendingSlot() }

		switch await ConfirmationRace.decide(timeout: timeout, sleep: sleep, inTurnOf: gate, ask: ask) {
		case true?: return .approved
		case false?: return .denied
		case nil: return .cancelledBeforePrompt
		}
	}

	private func reservePendingSlot() -> Bool {
		pendingPrompts.withLock { count in
			guard count < maxPendingPrompts else { return false }
			count += 1
			return true
		}
	}

	private func releasePendingSlot() {
		pendingPrompts.withLock { $0 -= 1 }
	}
}
