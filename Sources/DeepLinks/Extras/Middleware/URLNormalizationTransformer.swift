//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A URL transformer that normalizes deep link URLs for consistent processing.
///
/// This transformer performs several normalization operations to ensure URLs are
/// in a canonical form before parsing. It's useful as a first transformation step
/// in the middleware stack.
///
/// ## Normalization Operations
///
/// - **Path normalization**: Removes extra slashes and ensures paths start with `/`
/// - **Dot-segment resolution**: Resolves `.` and `..` path segments (including
///   percent-encoded `%2e`) without ever climbing above the root
///
/// Percent-encoded slashes (`%2F`) are decoded into separators before
/// dot segments resolve; backslashes are not separators.
///
/// - Important: Run this transformer before ``SecurityMiddleware``, or use
///   ``SecurityStrategy/hardened``. Validating first and normalizing later lets
///   `/public/%2e%2e/admin` pass a host or pattern check and then become `/admin`.
/// - **Empty parameter removal**: Removes query parameters with empty values
/// - **Component validation**: Ensures all URL components are valid
///
/// ## Usage
///
/// ```swift
/// // Use in middleware stack
/// let transformer = URLNormalizationTransformer()
/// coordinator.add(.urlTransformation(transformer: transformer))
///
/// // Example transformations:
/// // "myapp://profile//123" → "myapp://profile/123"
/// // "myapp://product?id=&name=Test" → "myapp://product?name=Test"
/// // "myapp://search/?query=test&lang=" → "myapp://search?query=test"
/// // "myapp://files/a/../../etc" → "myapp://files/etc"
/// ```
///
/// ## Thread Safety
///
/// This class is thread-safe and can be used concurrently across different
/// execution contexts.
public final class URLNormalizationTransformer: URLTransformer {
	/// Creates a new URL normalization transformer.
	///
	/// This initializer creates a transformer that will normalize URLs by cleaning
	/// up paths, removing empty parameters, and validating URL structure.
	public init() {}

	/// Normalizes a deep link URL by cleaning up its components.
	///
	/// This method performs the following normalizations:
	/// - Removes excess slashes from paths
	/// - Resolves `.` and `..` path segments, clamping at the root
	/// - Ensures paths start with `/` when not empty
	/// - Removes empty query parameters
	/// - Validates the resulting URL structure
	///
	/// ## Examples
	///
	/// ```swift
	/// let transformer = URLNormalizationTransformer()
	///
	/// // Path normalization
	/// let url1 = URL(string: "myapp://product//123")!
	/// let result1 = try transformer.transform(url1)
	/// // result1.path → "/product/123"
	///
	/// // Empty parameter removal
	/// let url2 = URL(string: "myapp://product?id=123&name=")!
	/// let result2 = try transformer.transform(url2)
	/// // Query parameters: ["id": "123"]
	///
	/// // Multiple operations
	/// let url3 = URL(string: "myapp://search/?query=test&lang=&")!
	/// let result3 = try transformer.transform(url3)
	/// // Query parameters: ["query": "test"]
	/// ```
	///
	/// - Parameter url: The URL to normalize
	/// - Returns: The normalized URL
	/// - Throws: `DeepLinkError.invalidURL` if the URL cannot be normalized or reconstructed
	public func transform(_ url: URL) throws -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			throw DeepLinkError.invalidURL(url)
		}

		components.path = Self.resolvingDotSegments(in: components.path)
			.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		if !components.path.isEmpty, !components.path.hasPrefix("/") {
			components.path = "/" + components.path
		}

		components.queryItems = components.queryItems?.filter { $0.value != nil && !$0.value!.isEmpty }

		guard let normalizedURL = components.url else {
			throw DeepLinkError.invalidURL(url)
		}

		return normalizedURL
	}

	static func resolvingDotSegments(in path: String) -> String {
		let isAbsolute = path.hasPrefix("/")
		let segments = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(isAbsolute ? 1 : 0)
		return (isAbsolute ? "/" : "") + URLText.resolvingDotSegments(segments).joined(separator: "/")
	}
}
