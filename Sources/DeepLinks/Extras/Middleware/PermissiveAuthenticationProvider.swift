//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// Permissive authentication provider that always returns true.
///
/// This is a convenience implementation of `AuthenticationProvider` that
/// always returns `true` for authentication checks. It's primarily useful
/// for development, testing, or when you want to disable authentication
/// temporarily.
///
/// ## Usage Scenarios
///
/// ### Development and Testing
/// ```swift
/// // Use during development when authentication is not yet implemented
/// let authProvider = PermissiveAuthenticationProvider()
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["secure.myapp.com"],
///     strategy: .standard
/// )
/// ```
///
/// ### Temporary Authentication Bypass
/// ```swift
/// // Use when you need to temporarily disable authentication
/// let authProvider = PermissiveAuthenticationProvider()
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["secure.myapp.com"],
///     strategy: .strict // Even strict strategy will allow all requests
/// )
/// ```
///
/// ### Testing Authentication Middleware Logic
/// ```swift
/// // Use in unit tests to verify middleware behavior without real auth
/// func testAuthenticationMiddleware() async throws {
///     let authProvider = PermissiveAuthenticationProvider()
///     let middleware = AuthenticationMiddleware(
///         authProvider: authProvider,
///         protectedHosts: ["secure.myapp.com"],
///         strategy: .standard
///     )
///
///     // This will always pass authentication
///     let url = URL(string: "https://secure.myapp.com/profile")!
///     let result = try await middleware.intercept(url)
///     XCTAssertEqual(result, url)
/// }
/// ```
///
/// ## Important Notes
///
/// - Never use in production unless you specifically want to disable authentication
/// - Perfect for development and testing environments
/// - Thread-safe and can be used across different execution contexts
/// - Lightweight implementation with minimal overhead
public final class PermissiveAuthenticationProvider: AuthenticationProvider {
	/// Creates a new permissive authentication provider.
	///
	/// This initializer creates an authentication provider that will
	/// always return `true` for authentication checks.
	public init() {}

	/// Always returns `true` indicating the user is authenticated.
	///
	/// This method always returns `true`, effectively bypassing all
	/// authentication checks when used with `AuthenticationMiddleware`.
	///
	/// - Returns: Always returns `true`
	public func isAuthenticated() -> Bool {
		true
	}
}
