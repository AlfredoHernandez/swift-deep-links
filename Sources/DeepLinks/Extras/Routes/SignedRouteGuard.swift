//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A handler decorator that runs protected routes only when their link's
/// signature was verified by ``SignedLinkMiddleware``.
///
/// This is the strongest signature rule: it checks the **parsed route**, so a
/// link reaching a protected screen through any URL spelling, host or parser
/// is rejected unless it was signed. ``SignedLinkMiddleware`` verifies every
/// link that carries a signature, whatever its URL rule says, and records the
/// result in ``DeepLinkContext/isSignatureVerified``, which entry points and
/// app code cannot set. Keep the middleware in the chain; without it no link
/// is ever verified and protected routes always fail (the guard fails
/// closed). ``SignedLinkMiddleware`` needs CryptoKit, so on a platform without
/// it the guard rejects every protected route.
///
/// ```swift
/// .handler(
///     AppHandler().requiringSignature(for: .routes {
///         if case .resetPassword = $0 { true } else { false }
///     })
/// )
/// ```
public struct SignedRouteGuard<Route: DeepLinkRoute>: DeepLinkHandler {
	/// The reason of the ``DeepLinkError/securityViolation(_:)`` thrown for an unsigned protected route.
	public static var unsignedRouteReason: String {
		"Route requires a signed link"
	}

	private let wrapped: any DeepLinkHandler<Route>
	private let matcher: RouteMatcher<Route>

	/// Creates a guard.
	///
	/// - Parameters:
	///   - handler: The handler that runs allowed routes.
	///   - matcher: The routes that need a verified signature.
	public init(_ handler: any DeepLinkHandler<Route>, requiredFor matcher: RouteMatcher<Route>) {
		wrapped = handler
		self.matcher = matcher
	}

	public func handle(_ route: Route, context: DeepLinkContext) async throws {
		if matcher.matches(route, context: context), !context.isSignatureVerified {
			throw DeepLinkError.securityViolation(Self.unsignedRouteReason)
		}
		try await wrapped.handle(route, context: context)
	}
}
