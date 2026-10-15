//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A structured representation of a deep link URL with parsed components.
///
/// `DeepLinkURL` provides a clean, structured interface for working with deep link URLs.
/// It parses the URL into its constituent parts and provides easy access to query parameters
/// as a dictionary, making it simple to extract information for route processing.
///
/// ## Usage
///
/// ```swift
/// let deepLinkURL = try DeepLinkURL(url: URL(string: "myapp://profile?userId=123")!)
/// print(deepLinkURL.scheme)    // "myapp"
/// print(deepLinkURL.host)      // "profile"
/// print(deepLinkURL.path)      // ""
/// print(deepLinkURL.queryParameters) // ["userId": "123"]
/// ```
///
/// ## URL Structure
///
/// For a URL like `myapp://profile?userId=123&name=John`:
/// - `scheme`: "myapp"
/// - `host`: "profile"
/// - `path`: "" (empty in this case)
/// - `queryParameters`: ["userId": "123", "name": "John"]
///
/// ## Error Handling
///
/// The initializer throws `DeepLinkError.invalidURL` if the URL cannot be parsed
/// or if required components (scheme, host) are missing.
///
/// ## Duplicate Parameters
///
/// By default a repeated key keeps its last value in ``queryParameters`` and
/// every value in ``allQueryParameters``. Code that reads one view while a
/// validator reads the other can disagree about the value (parameter
/// pollution). Pass `rejectDuplicateParameters: true` to reject such URLs.
public struct DeepLinkURL {
	/// The original URL
	public let url: URL

	/// The URL scheme (e.g., "myapp" from "myapp://...")
	public let scheme: String

	/// The URL host (e.g., "profile" from "myapp://profile")
	public let host: String

	/// The URL path component
	public let path: String

	/// Query parameters as a dictionary of key-value pairs
	///
	/// When multiple values exist for the same key, only the last value is retained.
	/// For array support, use `allQueryParameters` instead.
	public let queryParameters: [String: String]

	/// All query parameters including multiple values for the same key
	///
	/// This property supports array parameters in URLs like:
	/// `myapp://products?tags=electronics&tags=new&tags=sale`
	///
	/// Which would produce:
	/// ```
	/// ["tags": ["electronics", "new", "sale"]]
	/// ```
	public let allQueryParameters: [String: [String]]

	/// The default maximum URL length (8192 characters).
	///
	/// This limit prevents processing of excessively long URLs that could
	/// impact performance or be used for abuse.
	public static let defaultMaxLength = 8192

	/// Creates a new `DeepLinkURL` from a standard `URL`.
	///
	/// This initializer parses the URL and extracts all relevant components.
	/// It validates that the URL has both a scheme and host, and that the URL
	/// length does not exceed `maxLength`.
	///
	/// - Parameters:
	///   - url: The URL to parse
	///   - maxLength: Maximum allowed URL length in characters. Defaults to ``defaultMaxLength``.
	///   - rejectDuplicateParameters: When `true`, a query key that appears more than once
	///     (compared case-sensitively after percent-decoding, including valueless keys such
	///     as `?flag&flag`) makes the URL invalid. Defaults to `false`.
	/// - Throws: `DeepLinkError.invalidURL` if the URL is malformed, missing required components,
	///   exceeds `maxLength`, or repeats a query key while `rejectDuplicateParameters` is `true`
	public init(url: URL, maxLength: Int = Self.defaultMaxLength, rejectDuplicateParameters: Bool = false) throws(DeepLinkError) {
		guard url.absoluteString.count <= maxLength else {
			throw .invalidURL(url)
		}

		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let scheme = components.scheme, let host = components.host else {
			throw .invalidURL(url)
		}

		let queryItems = components.queryItems ?? []
		if rejectDuplicateParameters, Self.containsDuplicateKey(queryItems) {
			throw .invalidURL(url)
		}

		self.url = url
		self.scheme = scheme
		self.host = host
		path = components.path

		var singleParams: [String: String] = [:]
		for item in queryItems {
			guard let value = item.value else { continue }
			singleParams[item.name] = value // Last value wins for duplicates
		}
		queryParameters = singleParams

		var allParams: [String: [String]] = [:]
		for item in queryItems {
			guard let value = item.value else { continue }
			allParams[item.name, default: []].append(value)
		}
		allQueryParameters = allParams
	}

	static func containsDuplicateKey(_ queryItems: [URLQueryItem]) -> Bool {
		var seen: Set<String> = []
		return queryItems
			.filter { !$0.name.isEmpty || $0.value != nil }
			.contains { !seen.insert($0.name).inserted }
	}
}
