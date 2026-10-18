//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation
import Observation

/// Asks the user to confirm a deep link through a SwiftUI dialog.
///
/// ``ConfirmationMiddleware`` calls ``confirm(_:)`` and waits; the dialog
/// bound to ``prompt`` answers with ``answer(_:)``. When the middleware gives
/// up (its timeout, or the link is cancelled) the prompt is withdrawn and the
/// link is denied. A new prompt denies one still on screen, which happens
/// when the middleware moves on before the cancelled prompt is withdrawn.
@MainActor @Observable
final class ConfirmationPrompter: DeepLinkConfirmationProvider {
	/// A question waiting for the user.
	struct Prompt: Identifiable {
		let id = UUID()
		let message: String
		fileprivate let continuation: CheckedContinuation<Bool, Never>
	}

	private(set) var prompt: Prompt?

	func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
		let id = UUID()
		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				answer(false)
				prompt = Prompt(message: Self.message(for: request), continuation: continuation)
				promptID = id
			}
		} onCancel: {
			Task { @MainActor in self.settle(false, ifCurrent: id) }
		}
	}

	/// Answers the prompt on screen; does nothing when there is none.
	func answer(_ approved: Bool) {
		guard let promptID else { return }
		settle(approved, ifCurrent: promptID)
	}

	@ObservationIgnored private var promptID: UUID?

	private func settle(_ approved: Bool, ifCurrent id: UUID) {
		guard promptID == id, let pending = prompt else { return }
		prompt = nil
		promptID = nil
		pending.continuation.resume(returning: approved)
	}

	private static func message(for request: DeepLinkConfirmationRequest) -> String {
		"Open this \(request.url.host() ?? "deep") link?"
	}
}
