//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A handler decorator that runs protected routes only for a signed-in user.
///
/// This is the strongest authentication rule: it checks the **parsed
/// route** when the handler runs, so a link reaching a protected screen
/// through any URL spelling, host or parser is rejected unless
/// ``AuthenticationProvider/isAuthenticated()`` returns `true`.
/// ``AuthenticationMiddleware`` rules see the URL and stop links earlier (and
/// can save them to resume after sign-in); keep them as an early filter.
///
/// A rejected route throws ``DeepLinkError/unauthorizedAccess(_:)`` with the
/// URL the router received, or `about:blank` when called outside
/// ``DeepLinkCoordinator``. The route is not saved as a pending link.
///
/// ```swift
/// .handler(
///     AppHandler().requiringAuthentication(for: .routes {
///         if case .account = $0 { true } else { false }
///     }, provider: auth)
/// )
/// ```
public struct AuthenticatedHandler<Route: DeepLinkRoute>: DeepLinkHandler {
	private let wrapped: any DeepLinkHandler<Route>
	private let matcher: RouteMatcher<Route>
	private let provider: any AuthenticationProvider

	/// Creates an authenticating handler.
	///
	/// - Parameters:
	///   - handler: The handler that runs allowed routes.
	///   - matcher: The routes that need a signed-in user.
	///   - provider: Reports whether the user is signed in, checked each time a protected route runs.
	public init(_ handler: any DeepLinkHandler<Route>, requiredFor matcher: RouteMatcher<Route>, provider: any AuthenticationProvider) {
		wrapped = handler
		self.matcher = matcher
		self.provider = provider
	}

	public func handle(_ route: Route, context: DeepLinkContext) async throws {
		if matcher.matches(route, context: context), !provider.isAuthenticated() {
			throw DeepLinkRun.declineRoute(with: .unauthorizedAccess(DeepLinkRun.routedURL ?? URL(string: "about:blank")!))
		}
		try await wrapped.handle(route, context: context)
	}
}

// MARK: - Decorating Handlers

public extension DeepLinkHandler {
	/// This handler behind an ``AuthenticatedHandler`` for the routes `matcher` selects.
	func requiringAuthentication(for matcher: RouteMatcher<Route>, provider: any AuthenticationProvider) -> AuthenticatedHandler<Route> {
		AuthenticatedHandler(self, requiredFor: matcher, provider: provider)
	}
}
