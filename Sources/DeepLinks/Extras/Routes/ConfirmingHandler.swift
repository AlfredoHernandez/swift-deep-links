//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// A handler decorator that asks the user before protected routes run.
///
/// The route-level counterpart of ``ConfirmationMiddleware``: it decides on
/// the **parsed route**, so every URL spelling that reaches a protected screen
/// is confirmed, and the prompt can describe the action ("Send 10 € to Ana?")
/// rather than a URL. Denial, or no answer within `timeout`, throws
/// ``DeepLinkError/confirmationDenied(_:)`` with the URL the router received,
/// after middleware (so without signature parameters), or `about:blank` when
/// called outside ``DeepLinkCoordinator``. Like every error, it carries the
/// full URL: show or log its `redactedDescription`. The timeout
/// wins even if `confirm` ignores cancellation; dismiss your prompt when its
/// task is cancelled.
///
/// Prompts follow ``ConfirmationMiddleware``'s rules: they are shown one at a
/// time in arrival order, the timeout (60 seconds by default) counts from
/// arrival, and at most `maxPendingPrompts` routes (2 by default) wait or
/// prompt at once; a route beyond that throws
/// `securityViolation(ConfirmationMiddleware.tooManyPendingPromptsReason)`
/// without a prompt. Copies of a handler share the same prompt queue.
///
/// ```swift
/// .handler(
///     AppHandler().confirming(.routes { if case .payment = $0 { true } else { false } }) { route, _ in
///         await alerts.confirm(route.summary)
///     }
/// )
/// ```
public struct ConfirmingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
	/// The time a route may wait for an answer, prompt queue included, unless you pass another `timeout`.
	public static var defaultTimeout: Duration {
		ConfirmationMiddleware.defaultTimeout
	}

	/// How many routes may wait or prompt at once unless you pass another `maxPendingPrompts`.
	public static var defaultMaxPendingPrompts: Int {
		ConfirmationMiddleware.defaultMaxPendingPrompts
	}

	private let wrapped: any DeepLinkHandler<Route>
	private let matcher: RouteMatcher<Route>
	private let queue: ConfirmationQueue
	private let confirm: @Sendable (Route, DeepLinkContext) async -> Bool

	var maxPendingPrompts: Int {
		queue.maxPendingPrompts
	}

	/// Creates a confirming handler.
	///
	/// - Parameters:
	///   - handler: The handler that runs approved routes.
	///   - matcher: The routes that need confirmation.
	///   - timeout: How long a route waits for an answer, counted from its arrival
	///     (the wait for earlier prompts included), before it is denied. Defaults to
	///     ``defaultTimeout``; `nil` waits indefinitely. For signed links, keep it
	///     below the nonce store's reservation time to live.
	///   - maxPendingPrompts: How many routes may wait or prompt at once; more are
	///     rejected without a prompt. Defaults to ``defaultMaxPendingPrompts``; values below 1 count as 1.
	///   - sleep: Waits for the timeout; inject a controllable sleep in tests.
	///   - confirm: Asks the user; returns `true` to run the route.
	public init(
		_ handler: any DeepLinkHandler<Route>,
		requiredFor matcher: RouteMatcher<Route>,
		timeout: Duration? = ConfirmationMiddleware.defaultTimeout,
		maxPendingPrompts: Int = ConfirmationMiddleware.defaultMaxPendingPrompts,
		sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
		confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool,
	) {
		wrapped = handler
		self.matcher = matcher
		queue = ConfirmationQueue(timeout: timeout, maxPendingPrompts: maxPendingPrompts, sleep: sleep)
		self.confirm = confirm
	}

	/// Asks `confirm` about routes the matcher selects, then runs approved ones.
	///
	/// An unanswered prompt is denied when `timeout` elapses, and a route whose
	/// task is cancelled before its prompt is shown is denied without one. A
	/// declined or rejected route releases a signed link's nonce.
	///
	/// - Throws: ``DeepLinkError/confirmationDenied(_:)`` with the routed URL,
	///   ``DeepLinkError/securityViolation(_:)`` with
	///   ``ConfirmationMiddleware/tooManyPendingPromptsReason`` when
	///   `maxPendingPrompts` routes already wait, or whatever the wrapped handler throws.
	public func handle(_ route: Route, context: DeepLinkContext) async throws {
		if matcher.matches(route, context: context) {
			switch await queue.decide({ [confirm] in await confirm(route, context) }) {
			case .approved:
				break

			case .denied, .cancelledBeforePrompt:
				throw DeepLinkRun.declineRoute(with: .confirmationDenied(DeepLinkRun.routedURL ?? URL(string: "about:blank")!))

			case .overCapacity:
				throw DeepLinkRun.declineRoute(with: .securityViolation(ConfirmationMiddleware.tooManyPendingPromptsReason))
			}
		}
		try await wrapped.handle(route, context: context)
	}
}

// MARK: - Decorating Handlers

public extension DeepLinkHandler {
	/// This handler behind a ``SignedRouteGuard`` for the routes `matcher` selects.
	func requiringSignature(for matcher: RouteMatcher<Route>) -> SignedRouteGuard<Route> {
		SignedRouteGuard(self, requiredFor: matcher)
	}

	/// This handler behind a ``ConfirmingHandler`` for the routes `matcher` selects.
	func confirming(
		_ matcher: RouteMatcher<Route>,
		timeout: Duration? = ConfirmationMiddleware.defaultTimeout,
		maxPendingPrompts: Int = ConfirmationMiddleware.defaultMaxPendingPrompts,
		confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool,
	) -> ConfirmingHandler<Route> {
		ConfirmingHandler(self, requiredFor: matcher, timeout: timeout, maxPendingPrompts: maxPendingPrompts, confirm: confirm)
	}
}
