//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - `.hardened`: Canonicalizes the URL, then validates schemes, a required host,
///   and blocked patterns case-insensitively against decoded forms (recommended)
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
	/// This was the default before 2.0; ``hardened`` is the default now. An
	/// empty host allow-list accepts every host, including for `http(s)`.
	static let standard = SecurityStrategy { url, allowedSchemes, allowedHosts, blockedPatterns in
		guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		if !allowedHosts.isEmpty {
			guard let host = url.host, allowedHosts.contains(host) else {
				throw DeepLinkError.securityViolation("Unauthorized host")
			}
		}

		let urlString = url.absoluteString
		for pattern in blockedPatterns {
			if pattern.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
				throw DeepLinkError.blockedURL(url)
			}
		}

		return url
	}

	/// Hardened security strategy that validates the canonical form of the URL.
	///
	/// The URL is first canonicalized with ``URLCanonicalizer``, which rejects
	/// userinfo, control characters, `..` path segments (path only) and
	/// malformed percent-encoding. Then:
	///
	/// - the scheme must appear in the allowed schemes, compared case-insensitively;
	/// - `http(s)` URLs require a host listed in the allowed hosts, compared
	///   case-insensitively, so an empty host allow-list rejects every web link;
	/// - custom-scheme URLs must have a listed host when the allow-list is not
	///   empty; with an empty allow-list their host is not checked;
	/// - a URL with an authority but an empty host (`myapp:///account`) is
	///   rejected, so the first path segment cannot stand in for a host;
	/// - blocked patterns are matched case-insensitively against the raw URL
	///   and every percent-decoded form, so `%6A%61vascript:` matches `javascript:`.
	///   A pattern that cannot be recompiled case-insensitively rejects the URL.
	///
	/// On success the canonical URL (lower-cased scheme, decoded host without
	/// a trailing dot) continues down the chain.
	///
	/// ## Example
	///
	/// ```swift
	/// let middleware = SecurityMiddleware(
	///     allowedSchemes: ["https", "myapp"],
	///     allowedHosts: ["myapp.com", "home"],
	///     blockedPatterns: [try NSRegularExpression(pattern: "javascript:")],
	///     strategy: .hardened
	/// )
	/// ```
	static let hardened = SecurityStrategy { url, allowedSchemes, allowedHosts, blockedPatterns in
		let canonicalizer = URLCanonicalizer()
		let canonicalURL = try canonicalizer.canonicalize(url)

		guard let scheme = canonicalURL.scheme, allowedSchemes.containsCaseInsensitive(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		let isWebLink = webSchemes.contains(scheme)
		if hasEmptyAuthority(canonicalURL) {
			throw DeepLinkError.securityViolation("Missing host")
		}
		if isWebLink || !allowedHosts.isEmpty {
			guard let host = canonicalURL.host(), !host.isEmpty else {
				throw DeepLinkError.securityViolation("Missing host")
			}

			guard allowedHosts.containsCaseInsensitive(host) else {
				throw DeepLinkError.securityViolation("Unauthorized host")
			}
		}

		let forms = canonicalizer.matchableForms(of: url)
		for blockedPattern in blockedPatterns {
			let pattern = try caseInsensitiveRegex(pattern: blockedPattern.pattern, options: blockedPattern.options)
			if forms.contains(where: pattern.matches) {
				throw DeepLinkError.blockedURL(url)
			}
		}

		return canonicalURL
	}

	/// Strict security strategy that enforces scheme, host, and pattern checks.
	///
	/// Unlike ``standard``, this strategy always requires a host that appears in the
	/// allowed-host set; URLs without a host (or with a host not on the allowlist) are
	/// rejected outright.
	static let strict = SecurityStrategy { url, allowedSchemes, allowedHosts, blockedPatterns in
		guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		guard let host = url.host, allowedHosts.contains(host) else {
			throw DeepLinkError.securityViolation("Unauthorized host")
		}

		let urlString = url.absoluteString
		for pattern in blockedPatterns {
			if pattern.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
				throw DeepLinkError.blockedURL(url)
			}
		}

		return url
	}

	/// Permissive security strategy that only checks schemes.
	/// Allows all hosts and only blocks explicitly defined patterns.
	static let permissive = SecurityStrategy { url, allowedSchemes, _, blockedPatterns in
		guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		let urlString = url.absoluteString
		for pattern in blockedPatterns {
			if pattern.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
				throw DeepLinkError.blockedURL(url)
			}
		}

		return url
	}

	/// Scheme-only security strategy.
	/// Only validates URL schemes, ignores hosts and patterns.
	static let schemeOnly = SecurityStrategy { url, allowedSchemes, _, _ in
		guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		return url
	}

	/// Host-only security strategy.
	/// Only validates hosts, ignores schemes and patterns.
	static let hostOnly = SecurityStrategy { url, _, allowedHosts, _ in
		guard !allowedHosts.isEmpty else {
			return url
		}

		guard let host = url.host, allowedHosts.contains(host) else {
			throw DeepLinkError.securityViolation("Unauthorized host")
		}

		return url
	}

	/// Pattern-only security strategy.
	/// Only checks blocked patterns, ignores schemes and hosts.
	static let patternOnly = SecurityStrategy { url, _, _, blockedPatterns in
		let urlString = url.absoluteString
		for pattern in blockedPatterns {
			if pattern.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
				throw DeepLinkError.blockedURL(url)
			}
		}

		return url
	}

	/// Whitelist security strategy.
	/// Only allows URLs that match specific patterns (opposite of blacklist).
	static let whitelist = SecurityStrategy { url, allowedSchemes, allowedHosts, _ in
		guard let scheme = url.scheme, allowedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		if !allowedHosts.isEmpty {
			guard let host = url.host, allowedHosts.contains(host) else {
				throw DeepLinkError.securityViolation("Unauthorized host")
			}
		}

		guard url.path.hasPrefix("/") || url.path.isEmpty else {
			throw DeepLinkError.securityViolation("Invalid URL path format")
		}

		return url
	}
}

// MARK: - Hardened Matching Helpers

private let webSchemes: Set<String> = ["http", "https"]

/// `myapp:///account` has an authority with an empty host; a parser reading
/// the first path segment as the host would see `account`.
private func hasEmptyAuthority(_ url: URL) -> Bool {
	URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedHost?.isEmpty == true
}

private extension Set<String> {
	func containsCaseInsensitive(_ value: String) -> Bool {
		contains { $0.caseInsensitiveCompare(value) == .orderedSame }
	}
}

func caseInsensitiveRegex(
	pattern: String,
	options: NSRegularExpression.Options,
) throws(DeepLinkError) -> NSRegularExpression {
	do {
		return try NSRegularExpression(pattern: pattern, options: options.union(.caseInsensitive))
	} catch {
		throw .securityViolation("Invalid blocked pattern")
	}
}

private extension NSRegularExpression {
	func matches(_ text: String) -> Bool {
		firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
	}
}
