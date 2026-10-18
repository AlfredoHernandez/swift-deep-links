//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// Represents the parsed components of a deep link URL for logging purposes.
///
/// `DeepLinkComponents` provides a structured way to access and format the
/// different parts of a deep link URL. It's designed specifically for logging
/// middleware to extract and display URL information in various formats.
///
/// This struct is internal to the logging middleware but can be useful for implementing
/// custom logging formats or analyzing URL structure during debugging.
///
/// ## Usage Example
///
/// ```swift
/// let url = URL(string: "myapp://product/123?id=123&color=red")!
/// let components = DeepLinkComponents(from: url)
///
/// print(components.scheme) // "myapp"
/// print(components.host)   // "product"
/// print(components.path)   // "/123"
/// print(components.queryParametersString) // "id=123&color=red"
/// ```
///
/// ## URL Structure
///
/// For a URL like `myapp://product/123?id=123&color=red`:
/// - **Scheme**: `myapp` (the app identifier)
/// - **Host**: `product` (the route or feature)
/// - **Path**: `/123` (the resource identifier)
/// - **Query Items**: `id=123&color=red` (additional parameters)
///
/// ## Component Access
///
/// - Use `scheme`, `host`, `path` for direct component access
/// - Use `queryParametersString` for URL-encoded format
/// - Use `queryParametersDictionary` for structured access
/// - Use `hasQueryItems` to check if parameters exist
struct DeepLinkComponents {
	/// The URL scheme (e.g., "myapp" from "myapp://product/123").
	///
	/// This may be `nil` if the URL has no scheme component.
	let scheme: String?

	/// The URL host (e.g., "product" from "myapp://product/123").
	///
	/// This may be `nil` if the URL has no host component.
	let host: String?

	/// The URL path component (e.g., "/123" from "myapp://product/123").
	///
	/// This is an empty string if no path is present.
	let path: String

	/// The URL query items as an array of URLQueryItem objects.
	///
	/// This is `nil` if the URL has no query string.
	let queryItems: [URLQueryItem]?

	/// Creates a new `DeepLinkComponents` instance by parsing the given URL.
	///
	/// This initializer parses the URL into its constituent parts using URLComponents
	/// for reliable extraction of scheme, host, path, and query parameters.
	///
	/// - Parameter url: The deep link URL to parse
	init(from url: URL) {
		let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		scheme = components?.scheme
		host = components?.host.map(LogEscaping.singleLine)
		path = LogEscaping.singleLine(components?.path ?? "")
		queryItems = components?.queryItems
	}

	/// Indicates whether the URL contains query parameters.
	///
	/// This property checks if the URL has any query parameters by examining the
	/// `queryItems` array. It's useful for conditional formatting in logging.
	///
	/// - Returns: `true` if the URL has query parameters, `false` otherwise
	var hasQueryItems: Bool {
		guard let queryItems else { return false }
		return !queryItems.isEmpty
	}

	/// Returns query parameters as a formatted URL-encoded string.
	///
	/// Converts query items to a URL-encoded string format suitable for logging
	/// and display. For example: "id=123&color=red&size=large"
	///
	/// Parameters with `nil` values are represented as "nil" in the string.
	/// Decoded control characters are escaped (`\n`), so a value cannot add
	/// log lines. If no query parameters exist, returns an empty string.
	///
	/// ## Examples
	///
	/// ```swift
	/// // For URL: myapp://product?id=123&color=red
	/// // Returns: "id=123&color=red"
	///
	/// // For URL: myapp://product
	/// // Returns: ""
	/// ```
	///
	/// - Returns: A string representation of query parameters, or empty string if none exist
	var queryParametersString: String {
		guard let queryItems, !queryItems.isEmpty else { return "" }
		return queryItems.map { LogEscaping.singleLine("\($0.name)=\($0.value ?? "nil")") }.joined(separator: "&")
	}

	/// Returns query parameters as a dictionary.
	///
	/// Converts query items to a dictionary format suitable for JSON logging,
	/// structured data processing, and analytics. When multiple values exist for
	/// the same key, the last value is retained (standard dictionary behavior).
	///
	/// Parameters with `nil` values are represented as the string "nil".
	/// If no query parameters exist, returns an empty dictionary.
	///
	/// ## Examples
	///
	/// ```swift
	/// // For URL: myapp://product?id=123&color=red
	/// // Returns: ["id": "123", "color": "red"]
	///
	/// // For URL: myapp://product
	/// // Returns: [:]
	/// ```
	///
	/// - Returns: A dictionary with parameter names as keys and values as strings
	var queryParametersDictionary: [String: String] {
		guard let queryItems else { return [:] }
		return Dictionary(queryItems.map { ($0.name, $0.value ?? "nil") }, uniquingKeysWith: { _, last in last })
	}
}
