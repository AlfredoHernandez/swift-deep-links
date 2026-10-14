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

	/// Matches requests whose host is listed, case-insensitively and ignoring
	/// a trailing dot.
	///
	/// - Parameter hosts: The hosts to match.
	/// - Returns: A host matcher.
	static func hosts(_ hosts: Set<String>) -> DeepLinkMatcher {
		let normalizedHosts = Set(hosts.map(normalizedHost))
		return DeepLinkMatcher { request in
			request.url.host(percentEncoded: false).map { normalizedHosts.contains(normalizedHost($0)) } ?? false
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

// MARK: - Normalization

private extension DeepLinkMatcher {
	static func normalizedHost(_ host: String) -> String {
		let lowercased = host.lowercased()
		return lowercased.hasSuffix(".") ? String(lowercased.dropLast()) : lowercased
	}

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
		var paths: [String] = []
		for encodedPath in pathForms + customSchemeHostForms(of: url, paths: pathForms) {
			guard let decodedForms = decodedForms(of: encodedPath) else { return nil }
			paths += decodedForms.map(normalizedPath)
		}
		return paths
	}

	/// `myapp://reset/abc` reaches parsers as host `reset`, path `/abc`; also
	/// match it as `/reset/abc` so one rule covers web and custom-scheme links.
	static func customSchemeHostForms(of url: URL, paths: [String]) -> [String] {
		guard !["http", "https"].contains(url.scheme?.lowercased()),
		      let host = url.host(percentEncoded: true).map(normalizedHost), !host.isEmpty
		else { return [] }
		return paths.map { "/\(host)/\($0)" }
	}

	static func decodedForms(of encodedPath: String) -> [String]? {
		var encoded = encodedPath
		var forms = [encoded]
		for _ in 0 ..< URLCanonicalizer.maximumDecodingPasses {
			guard let decoded = encoded.removingPercentEncoding else { return nil }
			guard decoded != encoded else { return forms }
			forms.append(decoded)
			encoded = decoded
		}
		return encoded.removingPercentEncoding == encoded ? forms : nil
	}

	/// Collapses empty segments, treats `\\` as a separator, drops `;`
	/// parameters and invisible or control characters, resolves `.`/`..`,
	/// forces a leading `/` and lower-cases, so every spelling a lenient parser
	/// might accept reduces to the same path.
	static func normalizedPath(_ path: String) -> String {
		let visible = String(String.UnicodeScalarView(path.unicodeScalars.filter { !isInvisible($0) }))
		var segments: [Substring] = []
		for rawSegment in visible.split(whereSeparator: { $0 == "/" || $0 == "\\" }) {
			let segment = rawSegment.prefix { $0 != ";" }
			switch segment {
			case "", ".":
				continue

			case "..":
				_ = segments.popLast()

			default:
				segments.append(segment)
			}
		}
		return ("/" + segments.joined(separator: "/")).lowercased()
	}

	static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
		switch scalar.properties.generalCategory {
		case .control, .format, .lineSeparator, .paragraphSeparator: true
		default: false
		}
	}
}
