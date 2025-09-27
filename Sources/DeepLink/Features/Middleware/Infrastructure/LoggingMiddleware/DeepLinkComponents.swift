//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Represents the parsed components of a deep link URL for logging purposes.
///
/// `DeepLinkComponents` provides a structured way to access and format the
/// different parts of a deep link URL. It's designed specifically for logging
/// middleware to extract and display URL information in various formats.
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
struct DeepLinkComponents {
    /// The URL scheme (e.g., "myapp" from "myapp://product/123")
    let scheme: String?

    /// The URL host (e.g., "product" from "myapp://product/123")
    let host: String?

    /// The URL path (e.g., "/123" from "myapp://product/123")
    let path: String

    /// The URL query items as an array of URLQueryItem objects
    let queryItems: [URLQueryItem]?

    /// Creates a new `DeepLinkComponents` instance by parsing the given URL.
    ///
    /// - Parameter url: The deep link URL to parse
    init(from url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        scheme = components?.scheme
        host = components?.host
        path = components?.path ?? ""
        queryItems = components?.queryItems
    }

    /// Indicates whether the URL contains query parameters.
    ///
    /// - Returns: `true` if the URL has query parameters, `false` otherwise
    var hasQueryItems: Bool {
        guard let queryItems else { return false }
        return !queryItems.isEmpty
    }

    /// Returns query parameters as a formatted string.
    ///
    /// Converts query items to a URL-encoded string format suitable for logging.
    /// For example: "id=123&color=red&size=large"
    ///
    /// - Returns: A string representation of query parameters, or empty string if none exist
    var queryParametersString: String {
        guard let queryItems, !queryItems.isEmpty else { return "" }
        return queryItems.map { "\($0.name)=\($0.value ?? "nil")" }.joined(separator: "&")
    }

    /// Returns query parameters as a dictionary.
    ///
    /// Converts query items to a dictionary format suitable for JSON logging
    /// and structured data processing.
    ///
    /// - Returns: A dictionary with parameter names as keys and values as strings
    var queryParametersDictionary: [String: String] {
        guard let queryItems else { return [:] }
        return Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "nil") })
    }
}
