//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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
/// - `.whitelist`: An allow-list of schemes and hosts plus a path-format check;
///   despite its name it does not match patterns (see ``whitelist``)
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
///
/// ### Custom Strategies
///
/// Create your own strategy with ``init(_:)``. It receives each link and the
/// middleware's ``SecurityPolicy``, and returns the URL to continue with,
/// `nil` to stop the link quietly, or throws to reject it. Wrap a built-in
/// strategy to add a rule without losing its checks:
///
/// ```swift
/// let noAdmin = SecurityStrategy { url, policy in
///     guard !url.path().hasPrefix("/admin") else {
///         throw DeepLinkError.securityViolation("Admin links are not allowed")
///     }
///     return try await SecurityStrategy.hardened.validate(url: url, policy: policy)
/// }
/// let middleware = SecurityMiddleware(allowedSchemes: ["https"], allowedHosts: ["example.com"], strategy: noAdmin)
/// ```
public struct SecurityStrategy: Sendable {
	private let validateFunction: @Sendable (URL, SecurityPolicy) async throws -> URL?

	/// Creates a strategy that validates each link with `validate`.
	///
	/// - Parameter validate: Receives the link's URL and the middleware's
	///   policy; returns the URL to continue with (possibly rewritten), `nil`
	///   to stop the link without an error, or throws to reject it.
	public init(_ validate: @escaping @Sendable (_ url: URL, _ policy: SecurityPolicy) async throws -> URL?) {
		validateFunction = validate
	}

	/// Runs the strategy on `url`, so a custom strategy can delegate to a built-in one.
	///
	/// - Returns: The URL to continue with, or `nil` to stop the link.
	/// - Throws: The error the strategy rejects the link with.
	public func validate(url: URL, policy: SecurityPolicy) async throws -> URL? {
		try await validateFunction(url, policy)
	}
}

/// What a ``SecurityMiddleware`` allows, handed to its ``SecurityStrategy``.
///
/// Built once per middleware: allow-lists are normalized (schemes
/// lower-cased, hosts lower-cased without a trailing dot) and blocked
/// patterns recompiled case-insensitively here, not on every link.
public struct SecurityPolicy: Sendable {
	let normalizedSchemes: Set<String>
	let normalizedHosts: Set<String>
	let caseInsensitiveBlockedPatterns: Result<[NSRegularExpression], DeepLinkError>
	private let normalizedHostsByScheme: [String: Set<String>]

	/// Creates a policy, normalizing the allow-lists and recompiling the
	/// patterns case-insensitively; useful for unit-testing a custom strategy.
	public init(
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

	/// The allowed schemes, lower-cased.
	public var allowedSchemes: Set<String> {
		normalizedSchemes
	}

	/// The hosts allowed for every scheme, lower-cased and without a trailing
	/// dot; empty when the middleware lists none.
	public var allowedHosts: Set<String> {
		normalizedHosts
	}

	/// The normalized hosts allowed for `scheme`, compared case-insensitively,
	/// or `nil` when the middleware lists no hosts for that scheme.
	public func allowedHosts(forScheme scheme: String) -> Set<String>? {
		normalizedHosts(forScheme: scheme)
	}

	/// The blocked patterns, recompiled to match case-insensitively.
	///
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` with a
	///   ``SecurityViolationReason/invalidConfiguration`` reason when a pattern
	///   cannot be recompiled, so a strategy fails closed.
	public func blockedPatterns() throws(DeepLinkError) -> [NSRegularExpression] {
		try caseInsensitiveBlockedPatterns.get()
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
			throw DeepLinkError.securityViolation(SecurityViolationMessage.unauthorizedScheme)
		}

		if hasEmptyAuthority(canonicalURL) {
			throw DeepLinkError.securityViolation(SecurityViolationMessage.missingHost)
		}
		let listedHosts = policy.normalizedHosts(forScheme: scheme)
		if webSchemes.contains(scheme) || listedHosts != nil || !policy.normalizedHosts.isEmpty {
			guard let host = canonicalURL.host(), !host.isEmpty else {
				throw DeepLinkError.securityViolation(SecurityViolationMessage.missingHost)
			}

			guard (listedHosts ?? policy.normalizedHosts).contains(host) else {
				throw DeepLinkError.securityViolation(SecurityViolationMessage.unauthorizedHost)
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

	/// Allow-list strategy: requires an allowed scheme, an allowed host when
	/// hosts are listed, and a path that is empty or starts with `/`.
	///
	/// The name is historical: it does not match or require patterns, and it
	/// ignores `blockedPatterns`. Prefer ``hardened``, which also enforces the
	/// allow-lists and checks blocked patterns against every decoded form.
	static let whitelist = SecurityStrategy { url, policy in
		try requireScheme(of: url, in: policy)
		if !policy.normalizedHosts.isEmpty {
			try requireHost(of: url, in: policy.normalizedHosts)
		}

		guard url.path.hasPrefix("/") || url.path.isEmpty else {
			throw DeepLinkError.securityViolation(SecurityViolationMessage.invalidPath)
		}

		return url
	}
}

// MARK: - Shared Checks

/// Schemes compare case-insensitively.
private func requireScheme(of url: URL, in policy: SecurityPolicy) throws(DeepLinkError) {
	guard let scheme = url.scheme?.lowercased(), policy.normalizedSchemes.contains(scheme) else {
		throw .securityViolation(SecurityViolationMessage.unauthorizedScheme)
	}
}

/// Hosts compare case-insensitively, percent-decoded and without a trailing
/// dot, so `HOME`, `home.` and `%68ome` all match an allowed `home`.
private func requireHost(of url: URL, in normalizedHosts: Set<String>) throws(DeepLinkError) {
	guard let encodedHost = url.host(percentEncoded: true), !encodedHost.isEmpty,
	      normalizedHosts.contains(URLText.normalizedHost(URLText.decodedOnce(encodedHost)))
	else { throw .securityViolation(SecurityViolationMessage.unauthorizedHost) }
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
		throw .securityViolation(SecurityViolationMessage.invalidBlockedPattern)
	}
}

private extension NSRegularExpression {
	func matches(_ text: String) -> Bool {
		firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
	}
}
