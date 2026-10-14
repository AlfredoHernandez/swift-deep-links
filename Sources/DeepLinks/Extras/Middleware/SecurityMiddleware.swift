//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - `.hardened` (default): Canonicalizes the URL, requires an allowed host for
///   `http(s)`, and matches blocked patterns case-insensitively against decoded forms
/// - `.standard`: Validates schemes, hosts, and blocked patterns (the 1.x default)
/// - `.strict`: Enforces all security checks with additional validations
/// - `.permissive`: Only checks schemes and blocked patterns
/// - `.schemeOnly`: Only validates URL schemes
/// - `.hostOnly`: Only validates hosts
/// - `.patternOnly`: Only checks blocked patterns
/// - `.whitelist`: Only allows URLs matching specific patterns
///
/// ### Input Limits
/// ```swift
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https"],
///     allowedHosts: ["myapp.com"],
///     strategy: .hardened,
///     limits: .recommended
/// )
/// ```
/// Limits are checked before the strategy runs. Place the security middleware
/// first in the chain so oversized URLs are rejected before logging,
/// analytics or parsing process them.
///
/// ### Per-Source Policy
/// ```swift
/// // Payment links only through verified Universal Links
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https"],
///     allowedHosts: ["pay.myapp.com"],
///     allowedSources: [.universalLink],
///     strategy: .hardened
/// )
/// ```
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
	private let limits: DeepLinkInputLimits
	private let allowedSources: Set<DeepLinkContext.Source>?

	/// Creates a new security middleware.
	///
	/// - Parameters:
	///   - allowedSchemes: Set of allowed URL schemes
	///   - allowedHosts: Allowed hosts. With the default ``SecurityStrategy/hardened``,
	///     `http(s)` links require a listed host (empty rejects every web link)
	///     and custom-scheme hosts are checked only when the set is not empty
	///   - blockedPatterns: Array of regex patterns for blocked URLs
	///   - allowedSources: The ``DeepLinkContext/Source``s accepted, checked
	///     before anything else; `nil` (the default) accepts every source. A link
	///     intercepted as a bare URL has the ``DeepLinkContext/Source/unknown``
	///     source; links replayed from the built-in queues and stores keep theirs.
	///   - strategy: The security validation strategy to use (defaults to ``SecurityStrategy/hardened``;
	///     pass `.standard` for the 1.x behavior)
	///   - limits: Size limits checked before the strategy runs (defaults to ``DeepLinkInputLimits/unlimited``)
	public init(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		blockedPatterns: [NSRegularExpression] = [],
		allowedSources: Set<DeepLinkContext.Source>? = nil,
		strategy: SecurityStrategy = .hardened,
		limits: DeepLinkInputLimits = .unlimited,
	) {
		self.allowedSchemes = allowedSchemes
		self.allowedHosts = allowedHosts
		self.blockedPatterns = blockedPatterns
		self.strategy = strategy
		self.limits = limits
		self.allowedSources = allowedSources
	}

	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		if let allowedSources, !allowedSources.contains(request.context.source) {
			throw DeepLinkError.securityViolation("Source not allowed")
		}
		try limits.validate(request.url)
		let validated = try await strategy.validate(
			url: request.url,
			allowedSchemes: allowedSchemes,
			allowedHosts: allowedHosts,
			blockedPatterns: blockedPatterns,
		)
		return validated.map(request.replacingURL)
	}
}
