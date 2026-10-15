//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware for authentication validation.
///
/// This middleware validates that the user is authenticated before processing
/// certain deep links. It supports multiple authentication strategies and allows
/// you to protect specific hosts or schemes from unauthorized access.
///
/// ## Features
/// - **Flexible protection**: Protect specific hosts or schemes
/// - **Multiple strategies**: Different validation approaches
/// - **Configurable providers**: Compatible with any authentication system
/// - **Error handling**: Throws appropriate errors for unauthorized access
///
/// ## Use Cases
/// - Protect sensitive deep links from unauthorized access
/// - Implement role-based access control
/// - Secure admin or premium features
/// - Integrate with existing authentication systems
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// // Create authentication provider
/// let authProvider = MyAuthenticationProvider()
///
/// // Create middleware with standard strategy
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["secure.myapp.com", "admin.myapp.com"],
///     strategy: .standard
/// )
///
/// // Add to coordinator
/// coordinator.addMiddleware(middleware)
/// ```
///
/// ### Strict Authentication
/// ```swift
/// // Require authentication for all URLs
/// let strictMiddleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: [],
///     strategy: .strict
/// )
/// ```
///
/// ### Scheme-Based Protection
/// ```swift
/// // Protect specific URL schemes
/// let schemeMiddleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["myapp-secure", "myapp-admin"],
///     strategy: .schemeBased
/// )
/// ```
///
/// ## Available Strategies
/// - `.standard`: Validates authentication for protected hosts, matched in every spelling
/// - `.strict`: Requires authentication for all URLs regardless of host protection
/// - `.permissive`: Never validates authentication, allows all URLs
/// - `.schemeBased`: Validates authentication based on URL scheme rather than host
///
/// ### Resuming After Sign-In
/// ```swift
/// let pendingLinks = InMemoryPendingLinkStore()
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["account"],
///     pendingLinks: pendingLinks
/// )
///
/// // After the user signs in:
/// await coordinator.resumePendingLinks(from: pendingLinks)
/// ```
///
/// ### Protecting Paths or Routes
/// ```swift
/// // URL rule: any DeepLinkMatcher
/// AuthenticationMiddleware(authProvider: authProvider, requiredFor: .paths(["/admin"]))
///
/// // Route rule (strongest): holds for every URL spelling that parses to the route
/// AppHandler().requiringAuthentication(for: .routes { $0.isPrivate }, provider: authProvider)
/// ```
///
/// ## Error Handling
/// When authentication fails, the middleware throws
/// `DeepLinkError.unauthorizedAccess(url)` carrying the full URL that was
/// blocked, which can be handled by your error handling logic.
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
public final class AuthenticationMiddleware: DeepLinkMiddleware {
	private let authorize: @Sendable (DeepLinkRequest) throws -> URL?
	private let pendingLinks: (any PendingLinkStore)?

	/// Creates a new authentication middleware.
	///
	/// - Parameters:
	///   - authProvider: The authentication provider to use
	///   - protectedHosts: Set of hosts that require authentication
	///   - strategy: The authentication validation strategy to use (defaults to .standard)
	///   - pendingLinks: Where to save a link rejected with
	///     ``DeepLinkError/unauthorizedAccess(_:)`` so it can be resumed after
	///     sign-in with ``DeepLinkCoordinator/resumePendingLinks(from:)``. The
	///     link is still rejected. Inside ``DeepLinkCoordinator`` the URL saved
	///     is the link as it entered the chain (signature included), also for a
	///     link drained from a readiness queue, because a resume runs the whole
	///     chain again; called directly, it is the URL
	///     this middleware received. Defaults to `nil`, which saves nothing.
	public init(
		authProvider: AuthenticationProvider,
		protectedHosts: Set<String>,
		strategy: AuthenticationStrategy = .standard,
		pendingLinks: (any PendingLinkStore)? = nil,
	) {
		authorize = { request in
			try strategy.validate(url: request.url, protectedHosts: protectedHosts, provider: authProvider)
		}
		self.pendingLinks = pendingLinks
	}

	/// Creates a middleware requiring authentication for the links `matcher` selects.
	///
	/// Use it to protect paths, sources or any other URL rule, for example
	/// `.paths(["/admin"])` under a public host. Like every URL rule it sees one
	/// spelling of the link; protect sensitive routes with
	/// ``DeepLinkHandler/requiringAuthentication(for:provider:)`` as well.
	///
	/// - Parameters:
	///   - authProvider: The authentication provider to use.
	///   - matcher: The links that require a signed-in user.
	///   - pendingLinks: Where to save rejected links; see
	///     ``init(authProvider:protectedHosts:strategy:pendingLinks:)``.
	public init(
		authProvider: AuthenticationProvider,
		requiredFor matcher: DeepLinkMatcher,
		pendingLinks: (any PendingLinkStore)? = nil,
	) {
		authorize = { request in
			guard matcher.matches(request), !authProvider.isAuthenticated() else { return request.url }
			throw DeepLinkError.unauthorizedAccess(request.url)
		}
		self.pendingLinks = pendingLinks
	}

	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		do {
			return try authorize(request).map(request.replacingURL)
		} catch let DeepLinkError.unauthorizedAccess(rejectedURL) {
			await pendingLinks?.save(DeepLinkRun.arrival ?? request.replacingURL(rejectedURL))
			throw DeepLinkError.unauthorizedAccess(rejectedURL)
		}
	}
}
