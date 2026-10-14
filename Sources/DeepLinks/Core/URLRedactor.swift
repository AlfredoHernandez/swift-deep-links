//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Removes secrets from deep link URLs before they reach logs, analytics,
/// error messages or notifications.
///
/// A parameter is sensitive when its percent-decoded name, compared
/// case-insensitively against ``sensitiveKeys``:
///
/// - equals a key, or has a word that equals a key or its plural. Words are
///   split at punctuation, camel case, acronyms and letter/digit boundaries,
///   so `refreshToken`, `APIKey`, `user.email`, `code1` and `keys` match;
/// - contains a key of ``minimumContainedKeyLength`` or more characters, so
///   `accesstoken` and `SESSIONID` match. Shorter keys (`key`, `code`) never
///   match inside a word, so `keyword` and `barcode` are kept.
///
/// Redaction replaces with ``placeholder``:
///
/// - the value of each sensitive query, fragment and path matrix
///   (`;jsessionid=`) parameter,
/// - any parameter value shaped like a JSON Web Token, whatever its name,
/// - sensitive values inside a parameter whose value is itself a URL
///   (`?redirect=https%3A%2F%2Fx%3Ftoken%3Dabc`), recursively,
/// - userinfo.
///
/// Scheme, host, plain path segments and other parameters are kept, so a
/// secret used as a path segment (`/reset/<token>`) is not redacted.
///
/// ## Example
///
/// ```swift
/// let redactor = URLRedactor()
/// redactor.redact(URL(string: "https://app.com/reset?token=abc&lang=en")!)
/// // https://app.com/reset?token=REDACTED&lang=en
/// ```
public struct URLRedactor: Sendable {
	/// The keys redacted by default: common names for tokens, codes,
	/// credentials, contact details and session identifiers.
	public static let defaultSensitiveKeys: Set<String> = [
		"token", "jwt", "bearer", "code", "otp", "pin", "nonce", "ticket",
		"password", "passwd", "pwd", "passcode", "secret", "key", "apikey", "credential", "credentials",
		"auth", "authorization", "session", "sid", "jsessionid", "cookie", "signature", "sig",
		"email", "mail", "phone", "ssn",
	]

	/// The text that replaces redacted values by default.
	public static let defaultPlaceholder = "REDACTED"

	/// Keys at least this long also match when contained in a longer name.
	public static let minimumContainedKeyLength = 5

	/// The lower-cased keys treated as sensitive.
	public let sensitiveKeys: Set<String>

	/// The text that replaces each redacted value.
	public let placeholder: String

	private let containedKeys: [String]

	/// Creates a redactor.
	///
	/// - Parameters:
	///   - sensitiveKeys: The keys to redact, compared case-insensitively. They
	///     replace ``defaultSensitiveKeys``; pass `URLRedactor.defaultSensitiveKeys.union([...])`
	///     to extend the defaults.
	///   - placeholder: The text that replaces each redacted value.
	public init(sensitiveKeys: Set<String> = Self.defaultSensitiveKeys, placeholder: String = Self.defaultPlaceholder) {
		self.sensitiveKeys = Set(sensitiveKeys.map { $0.lowercased() })
		self.placeholder = placeholder
		containedKeys = self.sensitiveKeys.filter { $0.count >= Self.minimumContainedKeyLength }.sorted()
	}

	/// Whether a parameter with this decoded name has its value redacted.
	///
	/// - Parameter parameterName: The percent-decoded parameter name.
	/// - Returns: `true` when the name matches a sensitive key as described in ``URLRedactor``.
	public func isSensitive(parameterName: String) -> Bool {
		let name = parameterName.lowercased()
		guard !name.isEmpty else { return false }
		if sensitiveKeys.contains(name) || containedKeys.contains(where: name.contains) {
			return true
		}
		return NameWords(parameterName).words.contains { word in
			sensitiveKeys.contains(word) || (word.hasSuffix("s") && sensitiveKeys.contains(String(word.dropLast())))
		}
	}

	/// Returns `url` with sensitive values and userinfo redacted.
	///
	/// - Parameter url: The URL to redact.
	/// - Returns: The redacted URL; `url` itself when nothing is sensitive, and
	///   `about:blank` for a URL that cannot be decomposed.
	public func redact(_ url: URL) -> URL {
		redact(url, nestingBudget: Self.maximumNestedURLDepth)
	}

	/// Returns `text` with every embedded `scheme://` URL redacted.
	func redactingURLs(in text: String) -> String {
		let embeddedURL = #/[A-Za-z][A-Za-z0-9+.\-]*://[^\s'"<>]+/#
		var result = text
		for match in text.matches(of: embeddedURL).reversed() {
			guard let url = URL(string: String(match.output)) else { continue }
			let redacted = redact(url)
			if redacted != url {
				result.replaceSubrange(match.range, with: redacted.absoluteString)
			}
		}
		return result
	}
}

// MARK: - Redaction Passes

private extension URLRedactor {
	static let maximumNestedURLDepth = 3
	static let pairValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#;/?"))
	static let unparseableURL: URL = {
		guard let url = URL(string: "about:blank") else { preconditionFailure("about:blank is a valid URL") }
		return url
	}()

	func redact(_ url: URL, nestingBudget: Int) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			return Self.unparseableURL
		}

		if components.percentEncodedUser != nil || components.percentEncodedPassword != nil {
			components.percentEncodedUser = encodedPlaceholder()
			components.percentEncodedPassword = nil
		}
		components.percentEncodedPath = redactingMatrixParameters(in: components.percentEncodedPath, nestingBudget: nestingBudget)
		components.percentEncodedQuery = components.percentEncodedQuery.map { redactingPairs(in: $0, separator: "&", nestingBudget: nestingBudget) }
		components.percentEncodedFragment = components.percentEncodedFragment.map { redactingPairs(in: $0, separator: "&", nestingBudget: nestingBudget) }

		guard let redacted = components.url else { return Self.unparseableURL }
		return redacted.absoluteString == url.absoluteString ? url : redacted
	}

	func redactingMatrixParameters(in encodedPath: String, nestingBudget: Int) -> String {
		guard encodedPath.contains(";") else { return encodedPath }
		return encodedPath.split(separator: "/", omittingEmptySubsequences: false)
			.map { segment in
				guard let separator = segment.firstIndex(of: ";") else { return String(segment) }
				let parameters = segment[segment.index(after: separator)...]
				return segment[...separator] + redactingPairs(in: String(parameters), separator: ";", nestingBudget: nestingBudget)
			}
			.joined(separator: "/")
	}

	func redactingPairs(in encoded: String, separator: Character, nestingBudget: Int) -> String {
		encoded.split(separator: separator, omittingEmptySubsequences: false)
			.map { pair in redactingPair(pair, nestingBudget: nestingBudget) }
			.joined(separator: String(separator))
	}

	func redactingPair(_ pair: Substring, nestingBudget: Int) -> String {
		guard let equals = pair.firstIndex(of: "=") else { return String(pair) }
		let encodedName = pair[..<equals]
		let encodedValue = pair[pair.index(after: equals)...]
		let name = encodedName.removingPercentEncoding ?? String(encodedName)
		let value = encodedValue.removingPercentEncoding ?? String(encodedValue)

		if isSensitive(parameterName: name) || JSONWebTokenShape.matches(value) {
			return "\(encodedName)=\(encodedPlaceholder())"
		}
		if let nestedValue = redactedNestedURL(value, nestingBudget: nestingBudget) {
			return "\(encodedName)=\(nestedValue.addingPercentEncoding(withAllowedCharacters: Self.pairValueAllowed) ?? encodedPlaceholder())"
		}
		return String(pair)
	}

	func redactedNestedURL(_ value: String, nestingBudget: Int) -> String? {
		guard nestingBudget > 0, value.contains(":"), let nested = URL(string: value), nested.scheme != nil else { return nil }
		let redacted = redact(nested, nestingBudget: nestingBudget - 1)
		return redacted == nested ? nil : redacted.absoluteString
	}

	func encodedPlaceholder() -> String {
		placeholder.addingPercentEncoding(withAllowedCharacters: Self.pairValueAllowed) ?? Self.defaultPlaceholder
	}
}

// MARK: - Name Words

/// Splits a parameter name into lower-cased words at punctuation, camel-case
/// (`refreshToken`), acronym (`APIKey`) and letter/digit (`token2`) boundaries.
private struct NameWords {
	private(set) var words: [String] = []

	init(_ name: String) {
		let characters = Array(name)
		var current = ""
		for (index, character) in characters.enumerated() {
			guard character.isLetter || character.isNumber else {
				flush(&current)
				continue
			}
			if let previous = current.last, Self.isBoundary(previous, character, next: characters[safe: index + 1]) {
				flush(&current)
			}
			current.append(character)
		}
		flush(&current)
	}

	private mutating func flush(_ current: inout String) {
		if !current.isEmpty {
			words.append(current.lowercased())
		}
		current = ""
	}

	private static func isBoundary(_ previous: Character, _ character: Character, next: Character?) -> Bool {
		if previous.isNumber != character.isNumber {
			return true
		}
		if previous.isLowercase, character.isUppercase {
			return true
		}
		return previous.isUppercase && character.isUppercase && next?.isLowercase == true
	}
}

private extension Array {
	subscript(safe index: Int) -> Element? {
		indices.contains(index) ? self[index] : nil
	}
}

// MARK: - JSON Web Token Shape

/// Matches values shaped like a JSON Web Token: three base64url segments
/// separated by dots, either starting with an encoded JSON header (`eyJ`) or
/// with every segment at least eight characters long.
private enum JSONWebTokenShape {
	private static let base64URLCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
	private static let minimumSegmentLength = 8

	static func matches(_ value: String) -> Bool {
		let segments = value.split(separator: ".", omittingEmptySubsequences: false)
		guard segments.count == 3, segments.allSatisfy(isBase64URL) else { return false }
		if value.hasPrefix("eyJ") {
			return !segments[0].isEmpty && !segments[1].isEmpty
		}
		return segments.allSatisfy { $0.count >= minimumSegmentLength }
	}

	private static func isBase64URL(_ segment: Substring) -> Bool {
		segment.unicodeScalars.allSatisfy(base64URLCharacters.contains)
	}
}
