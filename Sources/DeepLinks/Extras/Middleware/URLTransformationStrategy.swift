//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// URL transformation strategies for deep links.
///
/// This struct provides different strategies for transforming deep link URLs before
/// they reach the parsers, each implementing a different approach to URL modification
/// and error handling.
///
/// ## Features
/// - **Flexible transformation**: Multiple transformation approaches
/// - **Error handling**: Different strategies for handling transformation failures
/// - **Conditional processing**: Transform only specific URLs
/// - **Safe operations**: Options for graceful failure handling
///
/// ## Available Strategies
/// - `.standard`: Applies the transformer directly
/// - `.conditional`: Only transforms URLs matching certain criteria
/// - `.safe`: Returns original URL if transformation fails
/// - `.aggressive`: Applies multiple transformation passes
/// - `.selective`: Only transforms URLs that need normalization
/// - `.passthrough`: Never transforms URLs
/// - `.validation`: Validates URLs before transformation
///
/// ## Usage Examples
///
/// ### Standard Transformation
/// ```swift
/// let middleware = URLTransformationMiddleware(
///     transformer: URLNormalizationTransformer(),
///     strategy: .standard
/// )
/// ```
///
/// ### Safe Transformation
/// ```swift
/// let middleware = URLTransformationMiddleware(
///     transformer: customTransformer,
///     strategy: .safe // Returns original URL if transformation fails
/// )
/// ```
///
/// ### Conditional Transformation
/// ```swift
/// let middleware = URLTransformationMiddleware(
///     transformer: customTransformer,
///     strategy: .conditional // Only transforms specific URLs
/// )
/// ```
///
/// ### Passthrough Mode
/// ```swift
/// let middleware = URLTransformationMiddleware(
///     transformer: customTransformer,
///     strategy: .passthrough // Never transforms URLs
/// )
/// ```
public struct URLTransformationStrategy: Sendable {
	private let transformFunction: @Sendable (URL, URLTransformer) throws -> URL?

	init(_ transformFunction: @escaping @Sendable (URL, URLTransformer) throws -> URL?) {
		self.transformFunction = transformFunction
	}

	/// Executes the URL transformation strategy.
	func transform(url: URL, transformer: URLTransformer) throws -> URL? {
		try transformFunction(url, transformer)
	}
}

// MARK: - URL Transformation Strategy Implementations

public extension URLTransformationStrategy {
	/// Standard transformation strategy that applies the transformer directly.
	/// This is the default transformation approach.
	static let standard = URLTransformationStrategy { url, transformer in
		try transformer.transform(url)
	}

	/// Conditional transformation strategy that only transforms URLs matching certain criteria.
	/// Only transforms URLs with specific schemes or hosts.
	static let conditional = URLTransformationStrategy { url, transformer in
		guard let scheme = url.scheme, ["https", "http"].contains(scheme) else {
			return url
		}

		if let host = url.host, !host.isEmpty {
			return try transformer.transform(url)
		}

		return url
	}

	/// Safe transformation strategy that catches and handles transformation errors.
	/// Returns the original URL if transformation fails.
	static let safe = URLTransformationStrategy { url, transformer in
		do {
			return try transformer.transform(url)
		} catch {
			return url
		}
	}

	/// Aggressive transformation strategy that applies multiple transformation passes.
	/// Applies the transformer multiple times until no more changes occur.
	static let aggressive = URLTransformationStrategy { url, transformer in
		var currentURL = url
		var previousURL: URL?
		var iterations = 0
		let maxIterations = 5

		while currentURL != previousURL, iterations < maxIterations {
			previousURL = currentURL
			currentURL = try transformer.transform(currentURL)
			iterations += 1
		}

		return currentURL
	}

	/// Selective transformation strategy that only transforms specific URL components.
	/// Only transforms URLs that need normalization (e.g., have double slashes, empty params).
	static let selective = URLTransformationStrategy { url, transformer in
		let urlString = url.absoluteString

		let path = url.path
		let needsTransformation = path.contains("//") ||
			urlString.contains("?&") ||
			urlString.contains("&&") ||
			urlString.hasSuffix("?") ||
			urlString.hasSuffix("&")

		if needsTransformation {
			return try transformer.transform(url)
		}

		return url
	}

	/// Passthrough transformation strategy that never transforms URLs.
	/// Always returns the original URL without any transformation.
	static let passthrough = URLTransformationStrategy { url, _ in
		url
	}

	/// Validation transformation strategy that validates URLs before transformation.
	/// Only transforms valid URLs and throws errors for invalid ones.
	static let validation = URLTransformationStrategy { url, transformer in
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let scheme = components.scheme, !scheme.isEmpty,
		      let host = components.host, !host.isEmpty
		else {
			throw DeepLinkError.invalidURL(url)
		}

		return try transformer.transform(url)
	}
}
