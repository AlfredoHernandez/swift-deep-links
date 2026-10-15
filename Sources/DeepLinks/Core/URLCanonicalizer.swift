//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Produces a single canonical form of a deep link URL and rejects URLs whose
/// structure is commonly used to smuggle payloads past validators.
///
/// Canonicalization lower-cases the scheme and host (both are
/// case-insensitive per RFC 3986), percent-decodes the host when it decodes
/// to plain host characters, drops a trailing dot from the host
/// (`myapp://Account%2E/x` becomes `myapp://account/x`), and leaves the path,
/// query and fragment untouched. A host that decodes to a delimiter
/// (`%2F`, `%40`, `%25`) is rejected. A URL is rejected with ``DeepLinkError/securityViolation(_:)``
/// when it:
///
/// - exceeds the configured ``DeepLinkInputLimits`` (checked first, before any decoding),
/// - carries userinfo (`https://trusted.com@evil.com`),
/// - contains control characters in any percent-decoded form (`%00`, `%0A`, `%250A`),
/// - contains Unicode format or line/paragraph separator characters in any
///   form (`%E2%80%AE` right-to-left override, `%E2%80%8B` zero-width space,
///   `%E2%80%A8`), which also rejects the zero-width joiner inside emoji sequences,
/// - has a `..` path segment in any percent-decoded form (`%2e%2e`, `%252e%252e`, `..%5C`),
/// - has percent-encoding that does not decode to valid UTF-8 (`%C0%AE`), or
///   is nested more than ``maximumDecodingPasses`` levels deep.
///
/// Each decoding pass decodes every valid `%HH` escape and keeps invalid
/// escapes literally, so a stray `%zz` cannot hide what follows it.
/// The `..` check applies to the path only; `..` in the query or fragment
/// is left to the parser that reads those values.
///
/// ## Example
///
/// ```swift
/// let canonicalizer = URLCanonicalizer()
/// let url = try canonicalizer.canonicalize(URL(string: "MyApp://Home/Profile")!)
/// // myapp://home/Profile
/// ```
public struct URLCanonicalizer: Sendable {
	/// The number of percent-decoding passes inspected before a URL is
	/// considered maliciously nested.
	public static let maximumDecodingPasses = URLText.maximumDecodingPasses

	/// The size limits enforced before any other check.
	public let limits: DeepLinkInputLimits

	/// Creates a canonicalizer.
	///
	/// - Parameter limits: Size limits enforced before decoding the URL.
	///   Defaults to ``DeepLinkInputLimits/unlimited``.
	public init(limits: DeepLinkInputLimits = .unlimited) {
		self.limits = limits
	}

	/// Returns `url` with a lower-cased scheme and a canonical host.
	///
	/// - Parameter url: The URL to canonicalize.
	/// - Returns: The canonical URL; `url` itself when it is already canonical.
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` when the URL is rejected.
	public func canonicalize(_ url: URL) throws(DeepLinkError) -> URL {
		try limits.validate(url)

		guard url.user == nil, url.password == nil else {
			throw .securityViolation(SecurityViolationMessage.userinfo)
		}

		let decodedForms = try strictlyDecodedForms(of: url.absoluteString)
		guard !decodedForms.contains(where: containsControlCharacter) else {
			throw .securityViolation(SecurityViolationMessage.controlCharacters)
		}
		guard !decodedForms.contains(where: containsInvisibleFormatting) else {
			throw .securityViolation(SecurityViolationMessage.invisibleCharacters)
		}

		let decodedPaths = try strictlyDecodedForms(of: url.path(percentEncoded: true))
		guard !decodedPaths.contains(where: containsDotDotSegment) else {
			throw .securityViolation(SecurityViolationMessage.pathTraversal)
		}

		return try canonicalSchemeAndHost(of: url)
	}

	/// Every form of `url` that pattern matching should consider: the raw
	/// absolute string followed by the result of each successive
	/// percent-decoding pass, stopping when decoding no longer changes it.
	///
	/// - Parameter url: The URL whose forms to produce.
	/// - Returns: At least one string; the first is always `url.absoluteString`.
	public func matchableForms(of url: URL) -> [String] {
		URLText.DecodingPasses(of: url.absoluteString).forms
	}
}

// MARK: - Validation

private extension URLCanonicalizer {
	func strictlyDecodedForms(of encoded: String) throws(DeepLinkError) -> [String] {
		let passes = URLText.DecodingPasses(of: encoded)
		guard passes.isValidUTF8, !passes.decodesFurther else {
			throw .securityViolation(SecurityViolationMessage.malformedEncoding)
		}
		return passes.forms
	}

	func containsControlCharacter(_ text: String) -> Bool {
		text.unicodeScalars.contains(where: URLText.isControl)
	}

	func containsInvisibleFormatting(_ text: String) -> Bool {
		text.unicodeScalars.contains(where: URLText.isInvisibleFormatting)
	}

	func containsDotDotSegment(_ path: String) -> Bool {
		path.split(omittingEmptySubsequences: false, whereSeparator: URLText.isPathSeparator)
			.contains("..")
	}

	func canonicalSchemeAndHost(of url: URL) throws(DeepLinkError) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return url
		}

		let scheme = components.scheme?.lowercased()
		let host = try components.percentEncodedHost.map(canonicalHost)
		guard scheme != components.scheme || host != components.percentEncodedHost else {
			return url
		}

		components.scheme = scheme
		components.percentEncodedHost = host
		return components.url ?? url
	}

	/// Lower-cased, percent-decoded when it decodes to plain host characters,
	/// and without a trailing dot, so `Account%2E` and `account.` both become `account`.
	func canonicalHost(_ encodedHost: String) throws(DeepLinkError) -> String {
		var host = encodedHost
		if encodedHost.contains("%") {
			let decoded = URLText.DecodingPasses(of: encodedHost).forms.last ?? encodedHost
			guard decoded.unicodeScalars.allSatisfy({ !$0.isASCII || Self.plainHostCharacters.contains($0) }) else {
				throw .securityViolation(SecurityViolationMessage.malformedHost)
			}
			if decoded.unicodeScalars.allSatisfy(\.isASCII) {
				host = decoded
			}
		}
		return URLText.normalizedHost(host)
	}

	static let plainHostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~!$&'()*+,;="))
}
