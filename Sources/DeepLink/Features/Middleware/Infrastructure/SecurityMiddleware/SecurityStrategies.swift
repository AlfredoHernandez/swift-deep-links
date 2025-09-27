//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Security validation strategies for deep links.
///
/// This struct provides different strategies for validating deep link URLs against
/// security policies to prevent malicious attacks and ensure only authorized URLs are processed.
///
/// ## Features
/// - **Scheme validation**: Validate allowed URL schemes
/// - **Host validation**: Restrict access to specific hosts
/// - **Pattern blocking**: Block URLs matching regex patterns
/// - **Flexible strictness**: From permissive to strict validation
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
/// ## Usage Examples
///
/// ### Standard Security
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https", "myapp"],
///     allowedHosts: ["myapp.com"],
///     strategy: .standard
/// )
/// ```
///
/// ### Strict Security
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https"],
///     allowedHosts: ["trusted-domain.com"],
///     blockedPatterns: [try NSRegularExpression(pattern: "malicious")],
///     strategy: .strict
/// )
/// ```
///
/// ### Scheme-Only Validation
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["myapp"],
///     strategy: .schemeOnly
/// )
/// ```
///
/// ### Pattern-Based Blocking
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https"],
///     blockedPatterns: [try NSRegularExpression(pattern: "phishing")],
///     strategy: .patternOnly
/// )
/// ```
///
/// ## Strategy Comparison
///
/// | Strategy | Schemes | Hosts | Patterns | Additional Checks |
/// |----------|---------|-------|----------|-------------------|
/// | `.standard` | ✅ | ✅ | ✅ | ❌ |
/// | `.strict` | ✅ | ✅ | ✅ | ✅ |
/// | `.permissive` | ✅ | ❌ | ✅ | ❌ |
/// | `.schemeOnly` | ✅ | ❌ | ❌ | ❌ |
/// | `.hostOnly` | ❌ | ✅ | ❌ | ❌ |
/// | `.patternOnly` | ❌ | ❌ | ✅ | ❌ |
/// | `.whitelist` | ✅ | ✅ | ❌ | ✅ |
public struct SecurityStrategy: Sendable {
    private let validateFunction: @Sendable (URL, Set<String>, Set<String>, [NSRegularExpression]) async throws -> URL?

    init(_ validateFunction: @escaping @Sendable (URL, Set<String>, Set<String>, [NSRegularExpression]) async throws -> URL?) {
        self.validateFunction = validateFunction
    }

    /// Executes the security validation strategy.
    func validate(url: URL, allowedSchemes: Set<String>, allowedHosts: Set<String>, blockedPatterns: [NSRegularExpression]) async throws -> URL? {
        try await validateFunction(url, allowedSchemes, allowedHosts, blockedPatterns)
    }
}

// MARK: - Security Strategy Implementations

public extension SecurityStrategy {
    /// Standard security strategy that validates schemes, hosts, and blocked patterns.
    /// This is the default security validation approach.
    static let standard = SecurityStrategy { url, allowedSchemes, allowedHosts, blockedPatterns in
        // Check scheme
        guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
            throw DeepLinkError.securityViolation("Unauthorized scheme: \(url.scheme ?? "nil")")
        }

        // Check host if allowedHosts is not empty
        if !allowedHosts.isEmpty {
            guard let host = url.host, allowedHosts.contains(host) else {
                throw DeepLinkError.securityViolation("Unauthorized host: \(url.host ?? "nil")")
            }
        }

        // Check blocked patterns
        let urlString = url.absoluteString
        for pattern in blockedPatterns {
            if pattern.firstMatch(in: urlString, range: NSRange(location: 0, length: urlString.count)) != nil {
                throw DeepLinkError.blockedURL(urlString)
            }
        }

        return url
    }

    /// Strict security strategy that enforces all security checks.
    /// More restrictive than standard, includes additional validations.
    static let strict = SecurityStrategy { url, allowedSchemes, allowedHosts, blockedPatterns in
        // Check scheme (required)
        guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
            throw DeepLinkError.securityViolation("Unauthorized scheme: \(url.scheme ?? "nil")")
        }

        // Check host (required in strict mode)
        guard let host = url.host, allowedHosts.contains(host) else {
            throw DeepLinkError.securityViolation("Unauthorized host: \(url.host ?? "nil")")
        }

        // Check blocked patterns
        let urlString = url.absoluteString
        for pattern in blockedPatterns {
            if pattern.firstMatch(in: urlString, range: NSRange(location: 0, length: urlString.count)) != nil {
                throw DeepLinkError.blockedURL(urlString)
            }
        }

        // Additional strict validations
        // Check for suspicious characters in path
        if url.path.contains("..") || url.path.contains("//") {
            throw DeepLinkError.securityViolation("Suspicious path detected: \(url.path)")
        }

        // Check for suspicious query parameters
        if let query = url.query, query.contains("script") || query.contains("javascript") {
            throw DeepLinkError.securityViolation("Suspicious query parameters detected")
        }

        return url
    }

    /// Permissive security strategy that only checks schemes.
    /// Allows all hosts and only blocks explicitly defined patterns.
    static let permissive = SecurityStrategy { url, allowedSchemes, _, blockedPatterns in
        // Only check scheme
        guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
            throw DeepLinkError.securityViolation("Unauthorized scheme: \(url.scheme ?? "nil")")
        }

        // Check blocked patterns only
        let urlString = url.absoluteString
        for pattern in blockedPatterns {
            if pattern.firstMatch(in: urlString, range: NSRange(location: 0, length: urlString.count)) != nil {
                throw DeepLinkError.blockedURL(urlString)
            }
        }

        return url
    }

    /// Scheme-only security strategy.
    /// Only validates URL schemes, ignores hosts and patterns.
    static let schemeOnly = SecurityStrategy { url, allowedSchemes, _, _ in
        guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
            throw DeepLinkError.securityViolation("Unauthorized scheme: \(url.scheme ?? "nil")")
        }

        return url
    }

    /// Host-only security strategy.
    /// Only validates hosts, ignores schemes and patterns.
    static let hostOnly = SecurityStrategy { url, _, allowedHosts, _ in
        guard !allowedHosts.isEmpty else {
            return url // Allow all if no hosts specified
        }

        guard let host = url.host, allowedHosts.contains(host) else {
            throw DeepLinkError.securityViolation("Unauthorized host: \(url.host ?? "nil")")
        }

        return url
    }

    /// Pattern-only security strategy.
    /// Only checks blocked patterns, ignores schemes and hosts.
    static let patternOnly = SecurityStrategy { url, _, _, blockedPatterns in
        let urlString = url.absoluteString
        for pattern in blockedPatterns {
            if pattern.firstMatch(in: urlString, range: NSRange(location: 0, length: urlString.count)) != nil {
                throw DeepLinkError.blockedURL(urlString)
            }
        }

        return url
    }

    /// Whitelist security strategy.
    /// Only allows URLs that match specific patterns (opposite of blacklist).
    static let whitelist = SecurityStrategy { url, allowedSchemes, allowedHosts, _ in
        // Check scheme
        guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
            throw DeepLinkError.securityViolation("Unauthorized scheme: \(url.scheme ?? "nil")")
        }

        // Check host if specified
        if !allowedHosts.isEmpty {
            guard let host = url.host, allowedHosts.contains(host) else {
                throw DeepLinkError.securityViolation("Unauthorized host: \(url.host ?? "nil")")
            }
        }

        // Additional whitelist validation: ensure URL is in expected format
        guard url.path.hasPrefix("/") || url.path.isEmpty else {
            throw DeepLinkError.securityViolation("Invalid URL path format")
        }

        return url
    }
}
