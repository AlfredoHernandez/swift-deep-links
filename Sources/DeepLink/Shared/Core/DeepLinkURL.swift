//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
    public let queryParameters: [String: String]

    /// Creates a new `DeepLinkURL` from a standard `URL`.
    ///
    /// This initializer parses the URL and extracts all relevant components.
    /// It validates that the URL has both a scheme and host, throwing an error
    /// if these required components are missing.
    ///
    /// - Parameter url: The URL to parse
    /// - Throws: `DeepLinkError.invalidURL` if the URL is malformed or missing required components
    public init(url: URL) throws(DeepLinkError) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let scheme = components.scheme, let host = components.host else {
            throw .invalidURL(url)
        }

        self.url = url
        self.scheme = scheme
        self.host = host
        path = components.path

        queryParameters = Dictionary(uniqueKeysWithValues: components.queryItems?.compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name, value)
        } ?? [])
    }
}
