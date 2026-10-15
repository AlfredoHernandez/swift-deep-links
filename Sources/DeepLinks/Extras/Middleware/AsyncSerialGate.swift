//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// Runs async operations one at a time, in arrival order.
///
/// Actor isolation alone does not make a multi-step operation atomic: an
/// actor is reentrant at every `await`. The gate holds its slot for the
/// whole operation, so a read-modify-write that spans suspension points
/// cannot interleave with another one. A task cancelled before its turn
/// throws `CancellationError` without running its operation.
actor AsyncSerialGate {
	private var isOccupied = false
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func run<Value: Sendable>(_ operation: @Sendable () async throws -> Value) async throws -> Value {
		await enter()
		defer { leave() }
		try Task.checkCancellation()
		return try await operation()
	}

	private func enter() async {
		guard isOccupied else {
			isOccupied = true
			return
		}
		await withCheckedContinuation { waiters.append($0) }
	}

	private func leave() {
		guard !waiters.isEmpty else {
			isOccupied = false
			return
		}
		waiters.removeFirst().resume()
	}
}
