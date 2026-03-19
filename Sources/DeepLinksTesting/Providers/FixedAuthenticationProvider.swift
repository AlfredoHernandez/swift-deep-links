//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// An authentication provider that always returns a fixed value.
///
/// ```swift
/// // Always authenticated
/// let auth = FixedAuthenticationProvider(isAuthenticated: true)
///
/// // Always unauthenticated
/// let auth = FixedAuthenticationProvider(isAuthenticated: false)
/// ```
public struct FixedAuthenticationProvider: AuthenticationProvider, Sendable {
	private let authenticated: Bool

	/// Creates a provider with a fixed authentication state.
	///
	/// - Parameter isAuthenticated: The value to return from `isAuthenticated()`
	public init(isAuthenticated: Bool) {
		authenticated = isAuthenticated
	}

	public func isAuthenticated() -> Bool {
		authenticated
	}
}
