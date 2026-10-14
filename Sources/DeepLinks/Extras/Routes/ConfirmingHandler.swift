//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// ```swift
/// .handler(
///     AppHandler().confirming(.routes { if case .payment = $0 { true } else { false } }) { route, _ in
///         await alerts.confirm(route.summary)
///     }
/// )
/// ```
public struct ConfirmingHandler<Route: DeepLinkRoute>: DeepLinkHandler {
	private let wrapped: any DeepLinkHandler<Route>
	private let matcher: RouteMatcher<Route>
	private let timeout: Duration?
	private let sleep: @Sendable (Duration) async throws -> Void
	private let confirm: @Sendable (Route, DeepLinkContext) async -> Bool

	/// Creates a confirming handler.
	///
	/// - Parameters:
	///   - handler: The handler that runs approved routes.
	///   - matcher: The routes that need confirmation.
	///   - timeout: How long to wait for an answer before denying; `nil` (default) waits indefinitely.
	///   - sleep: Waits for the timeout; inject a controllable sleep in tests.
	///   - confirm: Asks the user; returns `true` to run the route.
	public init(
		_ handler: any DeepLinkHandler<Route>,
		requiredFor matcher: RouteMatcher<Route>,
		timeout: Duration? = nil,
		sleep: @Sendable @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
		confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool,
	) {
		wrapped = handler
		self.matcher = matcher
		self.timeout = timeout
		self.sleep = sleep
		self.confirm = confirm
	}

	public func handle(_ route: Route, context: DeepLinkContext) async throws {
		if matcher.matches(route, context: context) {
			let approved = await ConfirmationRace.decide(timeout: timeout, sleep: sleep) { [confirm] in
				await confirm(route, context)
			}
			guard approved else {
				throw DeepLinkError.confirmationDenied(DeepLinkRun.routedURL ?? URL(string: "about:blank")!)
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
		timeout: Duration? = nil,
		confirm: @Sendable @escaping (Route, DeepLinkContext) async -> Bool,
	) -> ConfirmingHandler<Route> {
		ConfirmingHandler(self, requiredFor: matcher, timeout: timeout, confirm: confirm)
	}
}
