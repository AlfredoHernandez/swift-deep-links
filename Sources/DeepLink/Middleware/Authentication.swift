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

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
///     func isAuthenticated() async -> Bool {
///         // Check if valid token exists in keychain
///         return await keychainService.hasValidToken()
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
    func isAuthenticated() async -> Bool
}

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
/// - ⚠️ **Never use in production** unless you specifically want to disable authentication
/// - ✅ Perfect for development and testing environments
/// - ✅ Thread-safe and can be used across different execution contexts
/// - ✅ Lightweight implementation with minimal overhead
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
    public func isAuthenticated() async -> Bool {
        true
    }
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Authentication validation strategies for deep links.
///
/// This struct provides different strategies for validating user authentication
/// when processing deep links. Each strategy implements a different approach
/// to determine when authentication is required.
///
/// ## Features
/// - **Flexible validation**: Multiple authentication approaches
/// - **Host-based protection**: Protect specific domains
/// - **Scheme-based protection**: Protect specific URL schemes
/// - **Configurable strictness**: From permissive to strict validation
///
/// ## Available Strategies
/// - `.standard`: Validates authentication for protected hosts, allows URLs without hosts
/// - `.strict`: Requires authentication for all URLs
/// - `.permissive`: Never validates authentication
/// - `.schemeBased`: Scheme-based validation instead of host-based
///
/// ## Usage Examples
///
/// ### Standard Protection
/// ```swift
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["secure.myapp.com"],
///     strategy: .standard
/// )
/// ```
///
/// ### Strict Authentication
/// ```swift
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: [],
///     strategy: .strict // Requires auth for all URLs
/// )
/// ```
///
/// ### Scheme-Based Protection
/// ```swift
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: ["myapp-secure"], // Treated as schemes
///     strategy: .schemeBased
/// )
/// ```
///
/// ### Permissive Mode
/// ```swift
/// let middleware = AuthenticationMiddleware(
///     authProvider: authProvider,
///     protectedHosts: [],
///     strategy: .permissive // No authentication required
/// )
/// ```
///
/// ## Strategy Comparison
///
/// | Strategy | Host Protection | Scheme Protection | No Host URLs | All URLs |
/// |----------|----------------|-------------------|--------------|----------|
/// | `.standard` | ✅ | ❌ | ✅ | ❌ |
/// | `.strict` | ❌ | ❌ | ❌ | ✅ |
/// | `.permissive` | ❌ | ❌ | ✅ | ✅ |
/// | `.schemeBased` | ❌ | ✅ | ✅ | ❌ |
public struct AuthenticationStrategy: Sendable {
    private let validateFunction: @Sendable (URL, Set<String>, AuthenticationProvider) async throws -> URL?

    init(_ validateFunction: @escaping @Sendable (URL, Set<String>, AuthenticationProvider) async throws -> URL?) {
        self.validateFunction = validateFunction
    }

    /// Executes the authentication validation strategy.
    func validate(url: URL, protectedHosts: Set<String>, provider: AuthenticationProvider) async throws -> URL? {
        try await validateFunction(url, protectedHosts, provider)
    }
}

// MARK: - Authentication Strategy Implementations

public extension AuthenticationStrategy {
    /// Standard authentication strategy that checks protected hosts.
    ///
    /// Validates authentication for URLs with hosts in the protected set.
    /// URLs without hosts (like custom schemes) are allowed by default.
    /// This is the most commonly used strategy for apps that have both public
    /// and private sections.
    ///
    /// ## Usage
    /// Perfect for apps with mixed public/private content where only specific
    /// hosts require authentication.
    ///
    /// ## Example
    /// ```swift
    /// let middleware = AuthenticationMiddleware(
    ///     authProvider: authProvider,
    ///     protectedHosts: ["secure.myapp.com", "admin.myapp.com"],
    ///     strategy: .standard
    /// )
    /// ```
    ///
    /// ## Behavior
    /// - ✅ `myapp://public-content` → No authentication required (no host)
    /// - ✅ `https://public.myapp.com/help` → No authentication required
    /// - 🔒 `https://secure.myapp.com/profile` → Authentication required
    /// - 🔒 `https://admin.myapp.com/dashboard` → Authentication required
    static let standard = AuthenticationStrategy { url, protectedHosts, provider in
        guard let host = url.host else {
            // Allow URLs without hosts (like custom schemes: myapp://)
            return url
        }

        guard protectedHosts.contains(host) else {
            // Allow URLs with unprotected hosts
            return url
        }

        let isAuthenticated = await provider.isAuthenticated()

        if !isAuthenticated {
            throw DeepLinkError.unauthorizedAccess(host)
        }

        return url
    }

    /// Strict authentication strategy that requires authentication for all URLs.
    ///
    /// Validates authentication regardless of host protection rules. This strategy
    /// is useful for apps that are entirely private and require authentication
    /// for any deep link access.
    ///
    /// ## Usage
    /// Ideal for enterprise apps, banking apps, or any app where all content
    /// requires user authentication.
    ///
    /// ## Example
    /// ```swift
    /// let middleware = AuthenticationMiddleware(
    ///     authProvider: authProvider,
    ///     protectedHosts: [], // Ignored by strict strategy
    ///     strategy: .strict
    /// )
    /// ```
    ///
    /// ## Behavior
    /// - 🔒 `https://any-host.com/anything` → Authentication required
    /// - 🔒 `myapp://public-content` → Authentication required
    /// - 🔒 `https://docs.myapp.com/help` → Authentication required
    static let strict = AuthenticationStrategy { url, _, provider in
        let isAuthenticated = await provider.isAuthenticated()

        if !isAuthenticated {
            let host = url.host ?? "unknown"
            throw DeepLinkError.unauthorizedAccess(host)
        }

        return url
    }

    /// Permissive authentication strategy that allows all URLs.
    ///
    /// Never validates authentication, always allows access. This strategy
    /// is useful for development, testing, or apps that are entirely public.
    ///
    /// ## Usage
    /// Perfect for public apps, marketing apps, or during development when
    /// you want to bypass authentication temporarily.
    ///
    /// ## Example
    /// ```swift
    /// let middleware = AuthenticationMiddleware(
    ///     authProvider: authProvider,
    ///     protectedHosts: [], // Ignored by permissive strategy
    ///     strategy: .permissive
    /// )
    /// ```
    ///
    /// ## Behavior
    /// - ✅ `https://any-host.com/anything` → No authentication required
    /// - ✅ `myapp://private-content` → No authentication required
    /// - ✅ `https://secure.myapp.com/admin` → No authentication required
    static let permissive = AuthenticationStrategy { url, _, _ in
        url
    }

    /// Scheme-based authentication strategy.
    ///
    /// Validates authentication based on URL scheme rather than host. This strategy
    /// treats the `protectedHosts` parameter as a set of protected schemes instead.
    ///
    /// ## Usage
    /// Useful when you want to protect certain URL schemes (like `myapp-secure://`)
    /// while allowing others (like `myapp://`) to be public.
    ///
    /// ## Example
    /// ```swift
    /// let middleware = AuthenticationMiddleware(
    ///     authProvider: authProvider,
    ///     protectedHosts: ["myapp-secure", "myapp-admin"], // Treated as schemes
    ///     strategy: .schemeBased
    /// )
    /// ```
    ///
    /// ## Behavior
    /// - ✅ `myapp://public-content` → No authentication required
    /// - ✅ `https://secure.myapp.com/profile` → No authentication required (different scheme)
    /// - 🔒 `myapp-secure://profile` → Authentication required
    /// - 🔒 `myapp-admin://dashboard` → Authentication required
    static let schemeBased = AuthenticationStrategy { url, protectedHosts, provider in
        guard let scheme = url.scheme else {
            return url
        }

        // Treat scheme as "host" for validation purposes
        if protectedHosts.contains(scheme) {
            let isAuthenticated = await provider.isAuthenticated()

            if !isAuthenticated {
                throw DeepLinkError.unauthorizedAccess(scheme)
            }
        }

        return url
    }
}
