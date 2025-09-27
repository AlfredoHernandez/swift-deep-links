//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware for security validation.
///
/// This middleware validates URLs against security policies to prevent
/// malicious deep links and ensure only authorized URLs are processed.
///
/// ## Features
/// - **Scheme validation**: Validate allowed URL schemes
/// - **Host validation**: Restrict access to specific hosts
/// - **Pattern blocking**: Block URLs matching regex patterns
/// - **Multiple strategies**: Different security validation approaches
///
/// ## Use Cases
/// - Prevent malicious deep link attacks
/// - Restrict access to specific domains
/// - Block suspicious URL patterns
/// - Implement security policies
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https", "myapp"],
///     allowedHosts: ["myapp.com", "secure.myapp.com"]
/// )
/// ```
///
/// ### Strict Security
/// ```swift
/// let strictMiddleware = SecurityMiddleware(
///     allowedSchemes: ["https"],
///     allowedHosts: ["trusted-domain.com"],
///     blockedPatterns: [try NSRegularExpression(pattern: "malicious")],
///     strategy: .strict
/// )
/// ```
///
/// ### Scheme-Only Validation
/// ```swift
/// let schemeMiddleware = SecurityMiddleware(
///     allowedSchemes: ["myapp"],
///     strategy: .schemeOnly
/// )
/// ```
///
/// ## Available Strategies
/// - `.standard`: Validates schemes, hosts, and blocked patterns
/// - `.strict`: Enforces all security checks with additional validations
/// - `.permissive`: Only checks schemes and blocked patterns
/// - `.schemeOnly`: Only validates URL schemes
/// - `.hostOnly`: Only validates hosts
/// - `.patternOnly`: Only checks blocked patterns
/// - `.whitelist`: Only allows URLs matching specific patterns
///
/// ## Error Handling
/// When security validation fails, the middleware throws appropriate `DeepLinkError`
/// types which can be handled by your error handling logic.
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
public final class SecurityMiddleware: DeepLinkMiddleware {
    private let allowedSchemes: Set<String>
    private let allowedHosts: Set<String>
    private let blockedPatterns: [NSRegularExpression]
    private let strategy: SecurityStrategy

    /// Creates a new security middleware.
    ///
    /// - Parameters:
    ///   - allowedSchemes: Set of allowed URL schemes
    ///   - allowedHosts: Set of allowed hosts (empty means all hosts are allowed)
    ///   - blockedPatterns: Array of regex patterns for blocked URLs
    ///   - strategy: The security validation strategy to use (defaults to .standard)
    public init(
        allowedSchemes: Set<String>,
        allowedHosts: Set<String> = [],
        blockedPatterns: [NSRegularExpression] = [],
        strategy: SecurityStrategy = .standard,
    ) {
        self.allowedSchemes = allowedSchemes
        self.allowedHosts = allowedHosts
        self.blockedPatterns = blockedPatterns
        self.strategy = strategy
    }

    public func intercept(_ url: URL) async throws -> URL? {
        try await strategy.validate(
            url: url,
            allowedSchemes: allowedSchemes,
            allowedHosts: allowedHosts,
            blockedPatterns: blockedPatterns,
        )
    }
}
