//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A ``DeepLinkParser`` driven by a declarative path template.
///
/// Templates are `/`-separated segments:
///
/// - a literal (`products`) matches that exact, case-sensitive segment;
/// - `:name` captures one segment;
/// - a trailing `*` captures every remaining segment (possibly none).
///
/// ```swift
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .parsers([
///         .pattern("/products/:id") { try .product(id: $0.int("id")) },
///         .pattern("/u/:handle/posts/*") { try .posts(handle: $0.string("handle"), path: $0.wildcard) },
///     ])
///     .handler(handler)
///     .build()
/// ```
///
/// ## Canonical path
///
/// The URL path is split on `/` *before* each segment is percent-decoded, so
/// an encoded `%2F` stays inside its segment instead of creating a new one.
/// Empty segments are ignored, so trailing and repeated slashes still match.
/// A segment that decodes to `.` or `..` throws
/// ``DeepLinkError/securityViolation(_:)`` whether or not the template would
/// match; decoding happens once, so `%252e%252e` stays the literal text
/// `%2e%2e` and fails the character-set check.
///
/// These checks are defence in depth, not a gate: ``DefaultDeepLinkRouting``
/// treats any parser error as "not mine" and tries the next parser, so a
/// laxer parser later in the list can still accept the URL. Reject traversal
/// before routing with `.security(..., strategy: .hardened)`.
///
/// ## Errors
///
/// - ``DeepLinkError/routeNotFound(_:)`` when the host or the path structure
///   does not match, so ``DefaultDeepLinkRouting`` tries the next parser;
/// - ``DeepLinkError/invalidParameterValue(name:value:)`` when a captured or
///   wildcard segment has a character outside `allowedCharacters` (the
///   wildcard reports the name `*`);
/// - ``DeepLinkError/invalidURL(_:)`` for malformed percent-encoding;
/// - whatever the `build` closure throws.
public struct PathPatternParser<Route: DeepLinkRoute>: DeepLinkParser {
	/// Which part of the URL the template describes.
	public enum Scope: Sendable {
		/// The path only (`https://example.com/products/42` → `/products/42`).
		case path

		/// The host, lower-cased, followed by the path. Suits custom-scheme
		/// links whose host is the first logical segment
		/// (`myapp://products/42` → `products/42`).
		case hostAndPath
	}

	/// ASCII letters, digits, `-`, `.`, `_` and `~` (RFC 3986 unreserved characters).
	public static var defaultAllowedCharacters: CharacterSet {
		CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
	}

	private let pattern: PathPattern
	private let hosts: Set<String>
	private let scope: Scope
	private let allowedCharacters: CharacterSet
	private let build: @Sendable (PathPatternMatch) throws -> Route

	/// Compiles `template` into a parser.
	///
	/// - Parameters:
	///   - template: The path template, for example `/products/:id`.
	///   - hosts: Hosts the URL must have, compared case-insensitively; empty accepts any host.
	///   - scope: Whether the template covers the path or the host and path.
	///   - allowedCharacters: Characters a decoded captured or wildcard segment may contain.
	///   - build: Produces the route from the captured values.
	/// - Throws: ``PathPatternError`` when the template is invalid.
	public init(
		_ template: String,
		hosts: Set<String> = [],
		scope: Scope = .path,
		allowedCharacters: CharacterSet = Self.defaultAllowedCharacters,
		build: @escaping @Sendable (PathPatternMatch) throws -> Route,
	) throws(PathPatternError) {
		pattern = try PathPattern(template)
		self.hosts = Set(hosts.map { $0.lowercased() })
		self.scope = scope
		self.allowedCharacters = allowedCharacters
		self.build = build
	}

	/// Returns the single route built from `url`'s captures.
	public func parse(from url: URL) async throws -> [Route] {
		let host = url.host()?.lowercased()
		if !hosts.isEmpty {
			guard let host, hosts.contains(host) else { throw DeepLinkError.routeNotFound(url) }
		}

		let segments = try decodedSegments(of: url, host: host)
		guard let captures = pattern.match(segments) else {
			throw DeepLinkError.routeNotFound(url)
		}

		try validate(captures)
		return try [build(PathPatternMatch(url: url, values: captures.values, wildcard: captures.wildcard))]
	}
}

// MARK: - Factory

public extension DeepLinkParser {
	/// Creates a ``PathPatternParser`` from a declarative path template.
	///
	/// See ``PathPatternParser/init(_:hosts:scope:allowedCharacters:build:)``.
	static func pattern<R: DeepLinkRoute>(
		_ template: String,
		hosts: Set<String> = [],
		scope: PathPatternParser<R>.Scope = .path,
		allowedCharacters: CharacterSet = PathPatternParser<R>.defaultAllowedCharacters,
		build: @escaping @Sendable (PathPatternMatch) throws -> R,
	) throws(PathPatternError) -> Self where Self == PathPatternParser<R> {
		try PathPatternParser(template, hosts: hosts, scope: scope, allowedCharacters: allowedCharacters, build: build)
	}
}

// MARK: - Canonical Segments

private extension PathPatternParser {
	func decodedSegments(of url: URL, host: String?) throws -> [String] {
		let pathSegments = try url.path(percentEncoded: true)
			.split(separator: "/")
			.map { try decode(String($0), in: url) }

		guard scope == .hostAndPath, let host, !host.isEmpty else {
			return pathSegments
		}
		return [host] + pathSegments
	}

	func decode(_ segment: String, in url: URL) throws -> String {
		guard let decoded = segment.removingPercentEncoding else {
			throw DeepLinkError.invalidURL(url)
		}
		guard decoded != ".", decoded != ".." else {
			throw DeepLinkError.securityViolation("Path traversal is not allowed")
		}
		return decoded
	}

	func validate(_ captures: PathPattern.Captures) throws {
		for (name, value) in captures.values.sorted(by: { $0.key < $1.key }) where !isAllowed(value) {
			throw DeepLinkError.invalidParameterValue(name: name, value: value)
		}
		if let invalid = captures.wildcard.first(where: { !isAllowed($0) }) {
			throw DeepLinkError.invalidParameterValue(name: PathPattern.wildcardName, value: invalid)
		}
	}

	func isAllowed(_ value: String) -> Bool {
		!value.isEmpty && value.unicodeScalars.allSatisfy(allowedCharacters.contains)
	}
}
