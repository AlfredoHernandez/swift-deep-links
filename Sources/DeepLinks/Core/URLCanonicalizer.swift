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
	public static let maximumDecodingPasses = 4

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
			throw .securityViolation("Userinfo is not allowed")
		}

		let decodedForms = try strictlyDecodedForms(of: url.absoluteString)
		guard !decodedForms.contains(where: containsControlCharacter) else {
			throw .securityViolation("Control characters are not allowed")
		}
		guard !decodedForms.contains(where: containsInvisibleFormatting) else {
			throw .securityViolation("Invisible formatting characters are not allowed")
		}

		let decodedPaths = try strictlyDecodedForms(of: url.path(percentEncoded: true))
		guard !decodedPaths.contains(where: containsDotDotSegment) else {
			throw .securityViolation("Path traversal is not allowed")
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
		DecodingPasses(of: url.absoluteString, limit: Self.maximumDecodingPasses).forms
	}
}

// MARK: - Validation

private extension URLCanonicalizer {
	func strictlyDecodedForms(of encoded: String) throws(DeepLinkError) -> [String] {
		let passes = DecodingPasses(of: encoded, limit: Self.maximumDecodingPasses)
		guard passes.isValidUTF8, !passes.decodesFurther else {
			throw .securityViolation("Malformed percent-encoding")
		}
		return passes.forms
	}

	func containsControlCharacter(_ text: String) -> Bool {
		text.unicodeScalars.contains { $0.properties.generalCategory == .control }
	}

	func containsInvisibleFormatting(_ text: String) -> Bool {
		text.unicodeScalars.contains { scalar in
			switch scalar.properties.generalCategory {
			case .format, .lineSeparator, .paragraphSeparator: true
			default: false
			}
		}
	}

	func containsDotDotSegment(_ path: String) -> Bool {
		path.split(omittingEmptySubsequences: false) { $0 == "/" || $0 == "\\" }
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
			let decoded = DecodingPasses(of: encodedHost, limit: Self.maximumDecodingPasses).forms.last ?? encodedHost
			guard decoded.unicodeScalars.allSatisfy({ !$0.isASCII || Self.plainHostCharacters.contains($0) }) else {
				throw .securityViolation("Malformed host")
			}
			if decoded.unicodeScalars.allSatisfy(\.isASCII) {
				host = decoded
			}
		}
		return DeepLinkMatcher.normalizedHost(host)
	}

	static let plainHostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~!$&'()*+,;="))
}

// MARK: - Percent Decoding

/// Successive percent-decoding passes. Each pass decodes every valid `%HH`
/// escape and keeps invalid ones literally, so an invalid escape such as a
/// decoded literal `%zz` cannot stop decoding and hide what follows it.
private struct DecodingPasses {
	private(set) var forms: [String]
	private(set) var isValidUTF8 = true
	private(set) var decodesFurther = false

	init(of encoded: String, limit: Int) {
		forms = [encoded]
		while let next = Self.decode(forms[forms.count - 1]), next.text != forms[forms.count - 1] {
			guard forms.count <= limit else {
				decodesFurther = true
				return
			}
			isValidUTF8 = isValidUTF8 && next.isValidUTF8
			forms.append(next.text)
		}
	}

	private static func decode(_ text: String) -> (text: String, isValidUTF8: Bool)? {
		let source = Array(text.utf8)
		var bytes: [UInt8] = []
		bytes.reserveCapacity(source.count)

		var index = 0
		while index < source.count {
			if source[index] == UInt8(ascii: "%"), index + 2 < source.count,
			   let high = hexValue(of: source[index + 1]), let low = hexValue(of: source[index + 2])
			{
				bytes.append(high << 4 | low)
				index += 3
			} else {
				bytes.append(source[index])
				index += 1
			}
		}

		if let valid = String(bytes: bytes, encoding: .utf8) {
			return (valid, true)
		}
		return (String(decoding: bytes, as: UTF8.self), false)
	}

	private static func hexValue(of byte: UInt8) -> UInt8? {
		switch byte {
		case UInt8(ascii: "0") ... UInt8(ascii: "9"):
			byte - UInt8(ascii: "0")

		case UInt8(ascii: "a") ... UInt8(ascii: "f"):
			byte - UInt8(ascii: "a") + 10

		case UInt8(ascii: "A") ... UInt8(ascii: "F"):
			byte - UInt8(ascii: "A") + 10

		default:
			nil
		}
	}
}
