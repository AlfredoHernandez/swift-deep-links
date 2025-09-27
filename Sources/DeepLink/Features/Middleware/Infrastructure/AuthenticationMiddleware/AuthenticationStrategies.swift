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
