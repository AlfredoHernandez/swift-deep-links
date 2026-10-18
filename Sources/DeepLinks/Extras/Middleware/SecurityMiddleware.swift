//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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
/// ### Hosts Per Scheme
/// ```swift
/// // example.com only as a Universal Link, "home" only as a custom-scheme host
/// let middleware = SecurityMiddleware(
///     allowedSchemes: ["https", "myapp"],
///     allowedHostsByScheme: ["https": ["example.com"], "myapp": ["home"]]
/// )
/// ```
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
	private let policy: SecurityPolicy
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
	///   - allowedHostsByScheme: Hosts allowed per scheme, keys compared
	///     case-insensitively. Checked by ``SecurityStrategy/hardened`` only (other
	///     strategies ignore it): a scheme with an entry requires a host from that
	///     entry, and `allowedHosts` does not apply to it; schemes without an entry
	///     fall back to `allowedHosts`. An empty entry rejects every link of that
	///     scheme. Use it so a Universal Link domain is not accepted as a
	///     custom-scheme host, or the other way round. Defaults to empty.
	///   - blockedPatterns: Array of regex patterns for blocked URLs
	///   - allowedSources: The ``DeepLinkContext/Source``s accepted, checked
	///     before anything else; `nil` (the default) accepts every source. A link
	///     intercepted as a bare URL has the ``DeepLinkContext/Source/unknown``
	///     source; links replayed from the built-in queues and stores keep theirs.
	///   - strategy: The security validation strategy to use (defaults to ``SecurityStrategy/hardened``;
	///     pass `.standard` for the 1.x allow-lists)
	///   - limits: Size limits checked before the strategy runs (defaults to ``DeepLinkInputLimits/recommended``; pass ``DeepLinkInputLimits/unlimited`` to lift
	/// them)
	public init(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		allowedHostsByScheme: [String: Set<String>] = [:],
		blockedPatterns: [NSRegularExpression] = [],
		allowedSources: Set<DeepLinkContext.Source>? = nil,
		strategy: SecurityStrategy = .hardened,
		limits: DeepLinkInputLimits = .recommended,
	) {
		policy = SecurityPolicy(
			allowedSchemes: allowedSchemes,
			allowedHosts: allowedHosts,
			allowedHostsByScheme: allowedHostsByScheme,
			blockedPatterns: blockedPatterns,
		)
		self.strategy = strategy
		self.limits = limits
		self.allowedSources = allowedSources
	}

	/// Checks, in order, the source against `allowedSources`, the input
	/// limits, then the strategy, before any later middleware reads the URL.
	///
	/// - Returns: The request with the URL the strategy returned (canonical
	///   for ``SecurityStrategy/hardened``), or `nil` when the strategy stops it.
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` or
	///   ``DeepLinkError/blockedURL(_:)``; the reason never echoes the rejected value.
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		if let allowedSources, !allowedSources.contains(request.context.source) {
			throw DeepLinkError.securityViolation(SecurityViolationMessage.unauthorizedSource)
		}
		try limits.validate(request.url)
		let validated = try await strategy.validate(url: request.url, policy: policy)
		return validated.map(request.replacingURL)
	}
}
