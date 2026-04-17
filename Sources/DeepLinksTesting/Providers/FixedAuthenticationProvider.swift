//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// An authentication provider that always returns a fixed boolean value.
///
/// `FixedAuthenticationProvider` is a simple authentication provider for tests
/// that always returns the same authentication state. Use it to test routes
/// that depend on authentication without implementing complex authentication logic.
///
/// ## Overview
///
/// Create a provider with a fixed authentication state:
///
///     // Test authenticated user behavior
///     let auth = FixedAuthenticationProvider(isAuthenticated: true)
///
///     // Test unauthenticated user behavior
///     let auth = FixedAuthenticationProvider(isAuthenticated: false)
///
/// ## Testing Authentication-Based Routes
///
/// Use with middleware or handlers that check authentication:
///
///     let auth = FixedAuthenticationProvider(isAuthenticated: true)
///     let middleware = AuthenticationMiddleware(provider: auth)
///
///     let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///         .routing(routing)
///         .handler(handler)
///         .build()
///
///     await coordinator.add(middleware)
///     await coordinator.handle(url: protectedURL)
///
/// - Note: This provider has no internal state and is immutable after initialization.
/// - Complexity: O(1).
/// - SeeAlso: `AuthenticationProvider`
public struct FixedAuthenticationProvider: AuthenticationProvider, Sendable {
	private let authenticated: Bool

	/// Creates a provider with a fixed authentication state.
	///
	/// Every call to `isAuthenticated()` will return this value.
	///
	/// - Parameter isAuthenticated: The fixed authentication state to return from `isAuthenticated()`
	public init(isAuthenticated: Bool) {
		authenticated = isAuthenticated
	}

	public func isAuthenticated() -> Bool {
		authenticated
	}
}
