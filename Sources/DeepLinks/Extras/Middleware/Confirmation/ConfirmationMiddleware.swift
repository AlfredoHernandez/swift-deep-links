//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

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
/// cannot stack dialogs. The timeout runs from the moment the link arrives,
/// including the wait for earlier prompts, so a link never waits longer than
/// `timeout` in total. At most `maxPendingPrompts` links wait or prompt at
/// once; a link beyond that is rejected at once with
/// `securityViolation(ConfirmationMiddleware.tooManyPendingPromptsReason)`,
/// so a flood of links cannot queue prompts the user has to dismiss one by
/// one. A link whose task is cancelled before its prompt is shown throws
/// `CancellationError` without being shown. On timeout the next link gets its
/// turn at once, so a provider that ignores cancellation can leave its
/// prompt on screen under the next one: dismiss it when its task is cancelled.
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
///     .confirmation(provider: AlertConfirmation(), requiredFor: .hosts(["pay", "delete-account"]))
/// )
/// ```
public final class ConfirmationMiddleware: DeepLinkMiddleware {
	/// The time a link may wait for an answer, prompt queue included, unless you pass another `timeout`.
	public static let defaultTimeout = Duration.seconds(60)

	/// How many links may wait or prompt at once unless you pass another `maxPendingPrompts`.
	public static let defaultMaxPendingPrompts = 2

	/// The reason of the ``DeepLinkError/securityViolation(_:)`` thrown for a link beyond `maxPendingPrompts`.
	public static var tooManyPendingPromptsReason: String {
		SecurityViolationMessage.tooManyPendingPrompts
	}

	private let provider: any DeepLinkConfirmationProvider
	private let matcher: DeepLinkMatcher
	private let redactor: URLRedactor
	private let queue: ConfirmationQueue

	var maxPendingPrompts: Int {
		queue.maxPendingPrompts
	}

	/// Creates a confirmation middleware.
	///
	/// - Parameters:
	///   - provider: Shows the prompt and returns the user's decision.
	///   - matcher: The links that need confirmation. Defaults to ``DeepLinkMatcher/all``.
	///   - redactor: Redacts the URL handed to the provider. Defaults to a default ``URLRedactor``.
	///   - timeout: How long a link waits for an answer, counted from its arrival
	///     (the wait for earlier prompts included), before it is denied. Defaults to
	///     ``defaultTimeout``; `nil` waits indefinitely. For signed links, keep it
	///     below the nonce store's reservation time to live.
	///   - maxPendingPrompts: How many links may wait or prompt at once; more are
	///     rejected without a prompt. Defaults to ``defaultMaxPendingPrompts``; values below 1 count as 1.
	///   - sleep: Waits for the timeout; inject a controllable sleep in tests.
	public init(
		provider: any DeepLinkConfirmationProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		redactor: URLRedactor = URLRedactor(),
		timeout: Duration? = ConfirmationMiddleware.defaultTimeout,
		maxPendingPrompts: Int = ConfirmationMiddleware.defaultMaxPendingPrompts,
		sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
	) {
		self.provider = provider
		self.matcher = matcher
		self.redactor = redactor
		queue = ConfirmationQueue(timeout: timeout, maxPendingPrompts: maxPendingPrompts, sleep: sleep)
	}

	/// Asks the provider about links the matcher selects and passes the rest through.
	///
	/// The provider sees the redacted URL. Prompts are serialized in arrival
	/// order, and the timeout counts from arrival, including the wait for
	/// earlier prompts. On timeout or cancellation the link is denied at once,
	/// even if the provider ignores cancellation.
	///
	/// - Returns: `request` unchanged when approved or not selected.
	/// - Throws: ``DeepLinkError/confirmationDenied(_:)`` when denied or
	///   unanswered, or ``DeepLinkError/securityViolation(_:)`` with
	///   ``tooManyPendingPromptsReason`` when `maxPendingPrompts` links already wait.
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard matcher.matches(request) else { return request }
		let prompt = DeepLinkConfirmationRequest(url: redactor.redact(request.url), context: request.context)
		switch await queue.decide({ [provider] in await provider.confirm(prompt) }) {
		case .approved:
			break

		case .denied:
			throw DeepLinkError.confirmationDenied(request.url)

		case .cancelledBeforePrompt:
			throw CancellationError()

		case .overCapacity:
			throw DeepLinkError.securityViolation(Self.tooManyPendingPromptsReason)
		}
		return request
	}
}
