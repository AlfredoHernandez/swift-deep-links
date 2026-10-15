//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Selects the deep links a policy middleware applies to, such as the links
/// ``SignedLinkMiddleware`` requires a signature for.
///
/// The built-in matchers err on the side of matching: hosts and paths compare
/// case-insensitively, and paths are matched after percent-decoding (up to
/// ``URLCanonicalizer/maximumDecodingPasses`` times), collapsing empty
/// segments, treating `\\` as a separator, dropping `;` parameters and
/// invisible characters, and resolving `.`/`..` segments, so an unusual
/// spelling of a protected path is still protected. A path that cannot be
/// decoded, or is still encoded after the last pass, matches every path
/// prefix. Place ``SecurityMiddleware`` with ``SecurityStrategy/hardened``
/// first so such spellings are rejected outright.
///
/// Custom-scheme links put their first component in the host
/// (`myapp://reset/abc` has host `reset` and path `/abc`), so for every scheme
/// other than `http(s)` ``paths(_:)`` also matches the host as the first
/// segment: `.paths(["/reset"])` covers both `https://example.com/reset` and
/// `myapp://reset`.
public struct DeepLinkMatcher: Sendable {
	private let predicate: @Sendable (DeepLinkRequest) -> Bool

	/// Creates a matcher from a predicate.
	///
	/// - Parameter predicate: Returns `true` for requests the policy applies to.
	public init(_ predicate: @escaping @Sendable (DeepLinkRequest) -> Bool) {
		self.predicate = predicate
	}

	/// Whether the policy applies to `request`.
	public func matches(_ request: DeepLinkRequest) -> Bool {
		predicate(request)
	}
}

// MARK: - Built-in Matchers

public extension DeepLinkMatcher {
	/// Matches every request.
	static let all = DeepLinkMatcher { _ in true }

	/// Matches requests whose host is listed, case-insensitively, after
	/// percent-decoding and ignoring a trailing dot.
	///
	/// A custom-scheme link without a host (`myapp:///account/x`,
	/// `myapp:/account`, `myapp:account/x`) is matched by its first path
	/// segment, because a lenient parser may read that segment as the host.
	/// A host that cannot be decoded matches.
	///
	/// - Parameter hosts: The hosts to match.
	/// - Returns: A host matcher.
	static func hosts(_ hosts: Set<String>) -> DeepLinkMatcher {
		let normalizedHosts = Set(hosts.map(URLText.normalizedHost))
		return DeepLinkMatcher { request in
			matchesHost(of: request.url, in: normalizedHosts)
		}
	}

	/// Matches requests whose path equals one of `prefixes` or continues it
	/// with a `/` (`/reset` matches `/reset` and `/reset/abc`, not `/resetting`).
	///
	/// - Parameter prefixes: Path prefixes; a missing leading `/` and a
	///   trailing `/` are ignored, and `/` matches every path.
	/// - Returns: A path-prefix matcher.
	static func paths(_ prefixes: Set<String>) -> DeepLinkMatcher {
		let normalizedPrefixes = prefixes.map(normalizedPrefix)
		return DeepLinkMatcher { request in
			guard let paths = matchablePaths(of: request.url) else { return true }
			return paths.contains { path in
				normalizedPrefixes.contains { prefix in
					prefix == "/" || path == prefix || path.hasPrefix(prefix + "/")
				}
			}
		}
	}

	/// Matches requests delivered through one of `sources`.
	///
	/// - Parameter sources: The delivering channels to match.
	/// - Returns: A source matcher.
	static func sources(_ sources: Set<DeepLinkContext.Source>) -> DeepLinkMatcher {
		DeepLinkMatcher { sources.contains($0.context.source) }
	}

	/// Matches links replayed by ``DeepLinkCoordinator/resumePendingLinks(from:)``
	/// (``DeepLinkContext/isResumedPendingLink``), for example to confirm them
	/// with ``ConfirmationMiddleware`` before they act.
	static let resumedPendingLinks = DeepLinkMatcher { $0.context.isResumedPendingLink }

	/// A matcher backed by a closure.
	///
	/// - Parameter predicate: Returns `true` for requests the policy applies to.
	/// - Returns: A matcher calling `predicate`.
	static func custom(_ predicate: @escaping @Sendable (DeepLinkRequest) -> Bool) -> DeepLinkMatcher {
		DeepLinkMatcher(predicate)
	}

	/// Matches when at least one of `matchers` matches.
	static func anyOf(_ matchers: DeepLinkMatcher...) -> DeepLinkMatcher {
		DeepLinkMatcher { request in matchers.contains { $0.matches(request) } }
	}

	/// Matches when every one of `matchers` matches.
	static func allOf(_ matchers: DeepLinkMatcher...) -> DeepLinkMatcher {
		DeepLinkMatcher { request in matchers.allSatisfy { $0.matches(request) } }
	}
}

// MARK: - Host Matching

extension DeepLinkMatcher {
	/// Whether any spelling of `url`'s host is in `normalizedHosts` (built
	/// with ``URLText/normalizedHost(_:)``); `true` when the host cannot be decoded.
	static func matchesHost(of url: URL, in normalizedHosts: Set<String>) -> Bool {
		guard let candidates = hostCandidates(of: url) else { return true }
		return candidates.contains(where: normalizedHosts.contains)
	}

	/// Every decoded, normalized form of the host, or of the first path
	/// segment of a hostless custom-scheme link; `nil` when a form cannot be decoded.
	private static func hostCandidates(of url: URL) -> [String]? {
		if let host = url.host(percentEncoded: true), !host.isEmpty {
			return URLText.strictDecodedForms(of: host)?.map(URLText.normalizedHost)
		}
		guard !["http", "https"].contains(url.scheme?.lowercased()) else { return [] }
		let pathForms = [url.path(percentEncoded: true)] + opaquePathForms(of: url)
		var candidates: [String] = []
		for encodedPath in pathForms {
			guard let decoded = URLText.strictDecodedForms(of: encodedPath) else { return nil }
			candidates += decoded.compactMap(firstSegment).map(URLText.normalizedHost)
		}
		return candidates
	}

	/// Collapses empty segments, treats `\\` as a separator, drops `;`
	/// parameters and invisible or control characters, resolves `.`/`..`,
	/// forces a leading `/` and lower-cases, so every spelling a lenient parser
	/// might accept reduces to the same path.
	static func normalizedPath(_ path: String) -> String {
		let visible = String(String.UnicodeScalarView(path.unicodeScalars.filter { !URLText.isInvisible($0) }))
		let segments = visible.split(whereSeparator: URLText.isPathSeparator)
			.map { $0.prefix { $0 != ";" } }
			.filter { !$0.isEmpty }
		return ("/" + URLText.resolvingDotSegments(segments).joined(separator: "/")).lowercased()
	}

	private static func firstSegment(of path: String) -> String? {
		path.split(whereSeparator: URLText.isPathSeparator).first.map(String.init)
	}
}

// MARK: - Normalization

private extension DeepLinkMatcher {
	static func normalizedPrefix(_ prefix: String) -> String {
		var path = prefix.lowercased()
		if !path.hasPrefix("/") {
			path = "/" + path
		}
		while path.count > 1, path.hasSuffix("/") {
			path.removeLast()
		}
		return path
	}

	/// Every decoded form of the raw and the RFC 3986-standardized path
	/// (they differ on `//..`), or `nil` when a form cannot be decoded or stays
	/// encoded past the decoding limit, so the caller fails closed.
	static func matchablePaths(of url: URL) -> [String]? {
		let pathForms = [url.path(percentEncoded: true), url.standardized.path(percentEncoded: true)]
			+ opaquePathForms(of: url)
		var paths: [String] = []
		for encodedPath in pathForms + customSchemeHostForms(of: url, paths: pathForms) {
			guard let decodedForms = URLText.strictDecodedForms(of: encodedPath) else { return nil }
			paths += decodedForms.map(normalizedPath)
		}
		return paths
	}

	/// `myapp:reset/abc` has no hierarchical path on some Foundation versions,
	/// so read it from the raw string: everything after `scheme:` up to `?`/`#`.
	static func opaquePathForms(of url: URL) -> [String] {
		let raw = url.absoluteString
		guard let colon = raw.firstIndex(of: ":") else { return [] }
		let afterScheme = raw[raw.index(after: colon)...]
		guard !afterScheme.hasPrefix("//") else { return [] }
		return [String(afterScheme.prefix { $0 != "?" && $0 != "#" })]
	}

	/// `myapp://reset/abc` reaches parsers as host `reset`, path `/abc`; also
	/// match it as `/reset/abc` so one rule covers web and custom-scheme links.
	static func customSchemeHostForms(of url: URL, paths: [String]) -> [String] {
		guard !["http", "https"].contains(url.scheme?.lowercased()),
		      let host = url.host(percentEncoded: true).map(URLText.normalizedHost), !host.isEmpty
		else { return [] }
		return paths.map { "/\(host)/\($0)" }
	}
}
