//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import os

/// A confirmation provider that answers with a fixed decision and records
/// every prompt it was asked to show.
///
///     let confirmation = CollectingConfirmation(approves: false)
///     let middleware = ConfirmationMiddleware(provider: confirmation, requiredFor: .hosts(["pay"]))
///
///     _ = try? await middleware.intercept(DeepLinkRequest(url: payURL))
///
///     #expect(confirmation.requests.map(\.context.source) == [.unknown])
///
/// - Thread Safety: Lock-protected; safe from any task.
public final class CollectingConfirmation: DeepLinkConfirmationProvider {
	private struct State {
		var approves: Bool
		var requests: [DeepLinkConfirmationRequest] = []
	}

	private let state: OSAllocatedUnfairLock<State>

	/// Creates a provider.
	///
	/// - Parameter approves: The decision returned for every prompt.
	public init(approves: Bool) {
		state = OSAllocatedUnfairLock(initialState: State(approves: approves))
	}

	/// The decision returned for the next prompts.
	public var approves: Bool {
		get { state.withLock { $0.approves } }
		set { state.withLock { $0.approves = newValue } }
	}

	/// Every prompt received, in order.
	public var requests: [DeepLinkConfirmationRequest] {
		state.withLock { $0.requests }
	}

	/// Records `request` and answers with ``approves`` immediately, without
	/// suspending, so it never triggers a confirmation timeout.
	public func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
		state.withLock { state in
			state.requests.append(request)
			return state.approves
		}
	}
}
