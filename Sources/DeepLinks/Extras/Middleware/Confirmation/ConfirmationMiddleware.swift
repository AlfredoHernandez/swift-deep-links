//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// Middleware that asks the user to confirm sensitive deep links, such as
/// payments, deletions or account changes, before they continue.
///
/// For each link the ``DeepLinkMatcher`` selects, the
/// ``DeepLinkConfirmationProvider`` receives the link redacted with
/// `redactor` and its ``DeepLinkContext``. Approval passes the request on
/// unchanged; denial, or no answer within `timeout`, throws
/// ``DeepLinkError/confirmationDenied(_:)``. Other links pass through untouched.
///
/// Prompts are shown one at a time, in arrival order, so a burst of links
/// cannot stack dialogs; a link whose task is cancelled while waiting for its
/// turn throws `CancellationError` without being shown.
///
/// ## Placement
///
/// After ``ReadinessMiddleware`` (so the app can present UI) and after
/// security, signature, replay and authentication checks, so the user is
/// never asked about a link that would be rejected anyway.
///
/// ```swift
/// .middleware(
///     .security(allowedSchemes: ["myapp"]),
///     .rateLimit(maxRequests: 10, timeWindow: 60),
///     .readiness(queue: queue),
///     .confirmation(provider: AlertConfirmation(), requiredFor: .hosts(["pay", "delete-account"]), timeout: .seconds(60))
/// )
/// ```
public final class ConfirmationMiddleware: DeepLinkMiddleware {
	private let provider: any DeepLinkConfirmationProvider
	private let matcher: DeepLinkMatcher
	private let redactor: URLRedactor
	private let timeout: Duration?
	private let sleep: @Sendable (Duration) async throws -> Void
	private let gate = AsyncSerialGate()

	/// Creates a confirmation middleware.
	///
	/// - Parameters:
	///   - provider: Shows the prompt and returns the user's decision.
	///   - matcher: The links that need confirmation. Defaults to ``DeepLinkMatcher/all``.
	///   - redactor: Redacts the URL handed to the provider. Defaults to a default ``URLRedactor``.
	///   - timeout: How long to wait for an answer before denying; `nil` (default) waits indefinitely.
	///   - sleep: Waits for the timeout; inject a controllable sleep in tests.
	public init(
		provider: any DeepLinkConfirmationProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		redactor: URLRedactor = URLRedactor(),
		timeout: Duration? = nil,
		sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
	) {
		self.provider = provider
		self.matcher = matcher
		self.redactor = redactor
		self.timeout = timeout
		self.sleep = sleep
	}

	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard matcher.matches(request) else { return request }

		let prompt = DeepLinkConfirmationRequest(url: redactor.redact(request.url), context: request.context)
		guard try await gate.run({ try await self.answer(to: prompt) }) else {
			throw DeepLinkError.confirmationDenied(request.url)
		}
		return request
	}
}

// MARK: - Prompting

private extension ConfirmationMiddleware {
	/// Races the prompt against the timeout in unstructured tasks, so the first
	/// outcome returns (and frees the serial gate) even when the provider
	/// ignores cancellation. Cancelling the link denies it the same way.
	func answer(to prompt: DeepLinkConfirmationRequest) async throws -> Bool {
		guard let timeout else { return await provider.confirm(prompt) }

		let decision = FirstDecision()
		let promptTask = Task { [provider] in await decision.resolve(provider.confirm(prompt)) }
		let timerTask = Task { [sleep] in
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
private final class FirstDecision: Sendable {
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
