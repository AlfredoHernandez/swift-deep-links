//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - `.standard`: Validates authentication for protected hosts, allows URLs without hosts
/// - `.strict`: Requires authentication for all URLs regardless of host protection
/// - `.permissive`: Never validates authentication, allows all URLs
/// - `.schemeBased`: Validates authentication based on URL scheme rather than host
///
/// ## Error Handling
/// When authentication fails, the middleware throws `DeepLinkError.unauthorizedAccess(host)`
/// which can be handled by your error handling logic.
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
public final class AuthenticationMiddleware: DeepLinkMiddleware {
    private let authProvider: AuthenticationProvider
    private let protectedHosts: Set<String>
    private let strategy: AuthenticationStrategy

    /// Creates a new authentication middleware.
    ///
    /// - Parameters:
    ///   - authProvider: The authentication provider to use
    ///   - protectedHosts: Set of hosts that require authentication
    ///   - strategy: The authentication validation strategy to use (defaults to .standard)
    public init(
        authProvider: AuthenticationProvider,
        protectedHosts: Set<String>,
        strategy: AuthenticationStrategy = .standard,
    ) {
        self.authProvider = authProvider
        self.protectedHosts = protectedHosts
        self.strategy = strategy
    }

    public func intercept(_ url: URL) async throws -> URL? {
        try await strategy.validate(url: url, protectedHosts: protectedHosts, provider: authProvider)
    }
}
