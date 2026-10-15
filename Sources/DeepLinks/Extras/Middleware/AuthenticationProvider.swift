//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for authentication providers.
///
/// This protocol defines the contract for authentication providers used by
/// the `AuthenticationMiddleware`. Implementations should provide the current
/// authentication status of the user.
///
/// ## Usage
///
/// Authentication providers are used by the `AuthenticationMiddleware` to
/// determine whether a user is authenticated before allowing access to
/// protected deep links.
///
/// ## Implementation Example
///
/// ```swift
/// class KeychainAuthenticationProvider: AuthenticationProvider {
///     private let keychainService: KeychainService
///
///     init(keychainService: KeychainService) {
///         self.keychainService = keychainService
///     }
///
///     func isAuthenticated() -> Bool {
///         // Check if valid token exists in keychain
///         return keychainService.hasValidToken()
///     }
/// }
/// ```
///
/// ## Integration with AuthenticationMiddleware
///
/// ```swift
/// let authProvider = KeychainAuthenticationProvider(keychainService: keychain)
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["secure.myapp.com"],
///     strategy: .standard
/// )
/// ```
///
/// ## Thread Safety
///
/// This protocol is marked as `Sendable`, meaning implementations must be
/// thread-safe and can be used across different execution contexts.
public protocol AuthenticationProvider: Sendable {
	/// Determines whether the user is currently authenticated.
	///
	/// This method is called by the `AuthenticationMiddleware` to check
	/// the authentication status before allowing access to protected URLs.
	///
	/// - Returns: `true` if the user is authenticated, `false` otherwise
	func isAuthenticated() -> Bool
}
