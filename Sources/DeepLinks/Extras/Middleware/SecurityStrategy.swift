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
/// Every strategy compares schemes and hosts case-insensitively (hosts
/// percent-decoded and without a trailing dot) and matches blocked patterns
/// case-insensitively against the raw URL and each percent-decoded form;
/// they differ in which checks run and in what they return.
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
	private let validateFunction: @Sendable (URL, SecurityPolicy) async throws -> URL?

	init(_ validateFunction: @escaping @Sendable (URL, SecurityPolicy) async throws -> URL?) {
		self.validateFunction = validateFunction
	}

	/// Executes the security validation strategy.
	func validate(url: URL, policy: SecurityPolicy) async throws -> URL? {
		try await validateFunction(url, policy)
	}
}

/// What a ``SecurityMiddleware`` allows, handed to its ``SecurityStrategy``.
///
/// Built once per middleware: allow-lists are normalized (lower-cased, hosts
/// without a trailing dot) and blocked patterns recompiled case-insensitively
/// here, not on every link.
struct SecurityPolicy: Sendable {
	let normalizedSchemes: Set<String>
	let normalizedHosts: Set<String>
	let caseInsensitiveBlockedPatterns: Result<[NSRegularExpression], DeepLinkError>
	private let normalizedHostsByScheme: [String: Set<String>]

	init(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String> = [],
		allowedHostsByScheme: [String: Set<String>] = [:],
		blockedPatterns: [NSRegularExpression] = [],
	) {
		normalizedSchemes = Set(allowedSchemes.map { $0.lowercased() })
		normalizedHosts = Self.normalized(allowedHosts)
		normalizedHostsByScheme = Dictionary(
			allowedHostsByScheme.map { ($0.key.lowercased(), Self.normalized($0.value)) },
			uniquingKeysWith: { $0.union($1) },
		)
		caseInsensitiveBlockedPatterns = Result { () throws(DeepLinkError) in
			var compiled: [NSRegularExpression] = []
			for pattern in blockedPatterns {
				try compiled.append(caseInsensitiveRegex(pattern: pattern.pattern, options: pattern.options))
			}
			return compiled
		}
	}

	/// The normalized hosts listed for `scheme` in `allowedHostsByScheme`, or `nil` when it has no entry.
	func normalizedHosts(forScheme scheme: String) -> Set<String>? {
		normalizedHostsByScheme[scheme.lowercased()]
	}

	private static func normalized(_ hosts: Set<String>) -> Set<String> {
		Set(hosts.map(URLText.normalizedHost))
	}
}

// MARK: - Security Strategy Implementations

public extension SecurityStrategy {
	/// Standard security strategy that validates schemes, hosts, and blocked patterns.
	/// This was the default before 2.0; ``hardened`` is the default now. An
	/// empty host allow-list accepts every host, including for `http(s)`.
	static let standard = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		if !policy.normalizedHosts.isEmpty {
			try requireHost(of: url, in: policy.normalizedHosts)
		}
		try rejectBlocked(url, in: policy)
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
	/// - a scheme with an entry in `allowedHostsByScheme` requires a host from
	///   that entry instead, and the allowed hosts do not apply to it (an empty
	///   entry rejects every link of the scheme);
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
	static let hardened = SecurityStrategy { url, policy in
		let canonicalizer = URLCanonicalizer()
		let canonicalURL = try canonicalizer.canonicalize(url)

		guard let scheme = canonicalURL.scheme, policy.normalizedSchemes.contains(scheme) else {
			throw DeepLinkError.securityViolation("Unauthorized scheme")
		}

		if hasEmptyAuthority(canonicalURL) {
			throw DeepLinkError.securityViolation("Missing host")
		}
		let listedHosts = policy.normalizedHosts(forScheme: scheme)
		if webSchemes.contains(scheme) || listedHosts != nil || !policy.normalizedHosts.isEmpty {
			guard let host = canonicalURL.host(), !host.isEmpty else {
				throw DeepLinkError.securityViolation("Missing host")
			}

			guard (listedHosts ?? policy.normalizedHosts).contains(host) else {
				throw DeepLinkError.securityViolation("Unauthorized host")
			}
		}

		let forms = canonicalizer.matchableForms(of: url)
		for pattern in try policy.caseInsensitiveBlockedPatterns.get() where forms.contains(where: pattern.matches) {
			throw DeepLinkError.blockedURL(url)
		}

		return canonicalURL
	}

	/// Strict security strategy that enforces scheme, host, and pattern checks.
	///
	/// Unlike ``standard``, this strategy always requires a host that appears in the
	/// allowed-host set; URLs without a host (or with a host not on the allowlist) are
	/// rejected outright.
	static let strict = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		try requireHost(of: url, in: policy.normalizedHosts)
		try rejectBlocked(url, in: policy)
		return url
	}

	/// Permissive security strategy that only checks schemes.
	/// Allows all hosts and only blocks explicitly defined patterns.
	static let permissive = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		try rejectBlocked(url, in: policy)
		return url
	}

	/// Scheme-only security strategy.
	/// Only validates URL schemes, ignores hosts and patterns.
	static let schemeOnly = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		return url
	}

	/// Host-only security strategy.
	/// Only validates hosts, ignores schemes and patterns.
	static let hostOnly = SecurityStrategy { url, policy in
		if !policy.normalizedHosts.isEmpty {
			try requireHost(of: url, in: policy.normalizedHosts)
		}
		return url
	}

	/// Pattern-only security strategy.
	/// Only checks blocked patterns, ignores schemes and hosts.
	static let patternOnly = SecurityStrategy { url, policy in
		try rejectBlocked(url, in: policy)
		return url
	}

	/// Whitelist security strategy.
	/// Only allows URLs that match specific patterns (opposite of blacklist).
	static let whitelist = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		if !policy.normalizedHosts.isEmpty {
			try requireHost(of: url, in: policy.normalizedHosts)
		}

		guard url.path.hasPrefix("/") || url.path.isEmpty else {
			throw DeepLinkError.securityViolation("Invalid URL path format")
		}

		return url
	}
}

// MARK: - Shared Checks

/// Schemes compare case-insensitively.
private func requireScheme(of url: URL, in policy: SecurityPolicy) throws(DeepLinkError) {
	guard let scheme = url.scheme?.lowercased(), policy.normalizedSchemes.contains(scheme) else {
		throw .securityViolation("Unauthorized scheme")
	}
}

/// Hosts compare case-insensitively, percent-decoded and without a trailing
/// dot, so `HOME`, `home.` and `%68ome` all match an allowed `home`.
private func requireHost(of url: URL, in normalizedHosts: Set<String>) throws(DeepLinkError) {
	guard let encodedHost = url.host(percentEncoded: true), !encodedHost.isEmpty,
	      normalizedHosts.contains(URLText.normalizedHost(URLText.decodedOnce(encodedHost)))
	else { throw .securityViolation("Unauthorized host") }
}

/// Patterns match case-insensitively against the raw URL and every percent-decoded form.
private func rejectBlocked(_ url: URL, in policy: SecurityPolicy) throws(DeepLinkError) {
	let patterns = try policy.caseInsensitiveBlockedPatterns.get()
	guard !patterns.isEmpty else { return }
	let forms = URLCanonicalizer().matchableForms(of: url)
	if patterns.contains(where: { pattern in forms.contains(where: pattern.matches) }) {
		throw .blockedURL(url)
	}
}

// MARK: - Hardened Matching Helpers

private let webSchemes: Set<String> = ["http", "https"]

/// `myapp:///account` has an authority with an empty host; a parser reading
/// the first path segment as the host would see `account`.
private func hasEmptyAuthority(_ url: URL) -> Bool {
	URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedHost?.isEmpty == true
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
