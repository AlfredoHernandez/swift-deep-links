//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware for URL transformation.
///
/// This middleware can transform URLs before they reach the parsers,
/// useful for URL normalization, parameter injection, and other URL modifications.
///
/// ## Features
/// - **Flexible transformation**: Custom URL transformation logic
/// - **Multiple strategies**: Different transformation approaches
/// - **Error handling**: Graceful handling of transformation failures
/// - **Non-blocking flow**: The middleware doesn't interrupt normal deep link processing
///
/// ## Use Cases
/// - Normalize URLs for consistent processing
/// - Inject default parameters
/// - Redirect legacy URLs to new formats
/// - Clean and sanitize URLs
///
/// ## Usage Examples
///
/// ### Basic Usage
/// ```swift
/// let transformer = URLNormalizationTransformer()
/// let middleware = URLTransformationMiddleware(
///     transformer: transformer,
///     strategy: .standard
/// )
/// ```
///
/// ### Safe Transformation
/// ```swift
/// // Returns original URL if transformation fails
/// let safeMiddleware = URLTransformationMiddleware(
///     transformer: customTransformer,
///     strategy: .safe
/// )
/// ```
///
/// ### Conditional Transformation
/// ```swift
/// // Only transforms specific URLs
/// let conditionalMiddleware = URLTransformationMiddleware(
///     transformer: customTransformer,
///     strategy: .conditional
/// )
/// ```
///
/// ## Available Strategies
/// - `.standard`: Applies the transformer directly
/// - `.conditional`: Only transforms URLs matching certain criteria
/// - `.safe`: Returns original URL if transformation fails
/// - `.aggressive`: Applies multiple transformation passes
/// - `.selective`: Only transforms URLs that need normalization
/// - `.passthrough`: Never transforms URLs
/// - `.validation`: Validates URLs before transformation
/// - `.batch`: Applies multiple transformers in sequence
///
/// ## Error Handling
/// When transformation fails, the middleware behavior depends on the strategy:
/// - `.safe`: Returns the original URL
/// - `.standard`: Throws the transformation error
/// - `.passthrough`: Never fails
///
/// ## Thread Safety
/// This middleware is thread-safe and can be used concurrently.
public final class URLTransformationMiddleware: DeepLinkMiddleware {
	private let transformer: URLTransformer
	private let strategy: URLTransformationStrategy

	/// Creates a new URL transformation middleware.
	///
	/// - Parameters:
	///   - transformer: The URL transformer to use
	///   - strategy: The transformation strategy to use (defaults to .standard)
	public init(
		transformer: URLTransformer,
		strategy: URLTransformationStrategy = .standard,
	) {
		self.transformer = transformer
		self.strategy = strategy
	}

	public func intercept(_ url: URL) async throws -> URL? {
		try await strategy.transform(url: url, transformer: transformer)
	}
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// - `.batch`: Applies multiple transformers in sequence
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
///
/// ## Strategy Comparison
///
/// | Strategy | Error Handling | Conditional | Validation | Use Case |
/// |----------|----------------|-------------|------------|----------|
/// | `.standard` | Throws errors | ❌ | ❌ | Direct transformation |
/// | `.conditional` | Throws errors | ✅ | ❌ | Selective transformation |
/// | `.safe` | Returns original | ❌ | ❌ | Graceful failure |
/// | `.aggressive` | Throws errors | ❌ | ❌ | Multiple passes |
/// | `.selective` | Throws errors | ✅ | ❌ | Normalization only |
/// | `.passthrough` | Never fails | ❌ | ❌ | No transformation |
/// | `.validation` | Throws errors | ❌ | ✅ | Validated transformation |
/// | `.batch` | Throws errors | ❌ | ❌ | Sequential transformation |
public struct URLTransformationStrategy: Sendable {
	private let transformFunction: @Sendable (URL, URLTransformer) async throws -> URL?

	init(_ transformFunction: @escaping @Sendable (URL, URLTransformer) async throws -> URL?) {
		self.transformFunction = transformFunction
	}

	/// Executes the URL transformation strategy.
	func transform(url: URL, transformer: URLTransformer) async throws -> URL? {
		try await transformFunction(url, transformer)
	}
}

// MARK: - URL Transformation Strategy Implementations

public extension URLTransformationStrategy {
	/// Standard transformation strategy that applies the transformer directly.
	/// This is the default transformation approach.
	static let standard = URLTransformationStrategy { url, transformer in
		try await transformer.transform(url)
	}

	/// Conditional transformation strategy that only transforms URLs matching certain criteria.
	/// Only transforms URLs with specific schemes or hosts.
	static let conditional = URLTransformationStrategy { url, transformer in
		// Only transform URLs with specific schemes
		guard let scheme = url.scheme, ["https", "http"].contains(scheme) else {
			return url // Return original URL without transformation
		}

		// Only transform URLs with specific hosts (if any)
		if let host = url.host, !host.isEmpty {
			return try await transformer.transform(url)
		}

		return url
	}

	/// Safe transformation strategy that catches and handles transformation errors.
	/// Returns the original URL if transformation fails.
	static let safe = URLTransformationStrategy { url, transformer in
		do {
			return try await transformer.transform(url)
		} catch {
			// Log the error but return the original URL
			// This ensures the deep link processing continues even if transformation fails
			return url
		}
	}

	/// Aggressive transformation strategy that applies multiple transformation passes.
	/// Applies the transformer multiple times until no more changes occur.
	static let aggressive = URLTransformationStrategy { url, transformer in
		var currentURL = url
		var previousURL: URL?
		var iterations = 0
		let maxIterations = 5 // Prevent infinite loops

		while currentURL != previousURL, iterations < maxIterations {
			previousURL = currentURL
			currentURL = try await transformer.transform(currentURL)
			iterations += 1
		}

		return currentURL
	}

	/// Selective transformation strategy that only transforms specific URL components.
	/// Only transforms URLs that need normalization (e.g., have double slashes, empty params).
	static let selective = URLTransformationStrategy { url, transformer in
		let urlString = url.absoluteString

		// Check if URL needs transformation
		let needsTransformation = urlString.contains("//") ||
			urlString.contains("?&") ||
			urlString.contains("&&") ||
			urlString.hasSuffix("?") ||
			urlString.hasSuffix("&")

		if needsTransformation {
			return try await transformer.transform(url)
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
		// Validate URL structure before transformation
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let scheme = components.scheme, !scheme.isEmpty,
		      let host = components.host, !host.isEmpty
		else {
			throw DeepLinkError.invalidURL(url)
		}

		return try await transformer.transform(url)
	}

	/// Batch transformation strategy that applies multiple transformers in sequence.
	/// Note: This strategy requires a composite transformer that applies multiple transformations.
	static let batch = URLTransformationStrategy { url, transformer in
		// For batch transformation, we apply the transformer multiple times
		// This simulates having multiple transformers applied in sequence
		var result = url

		// Apply transformation twice to simulate batch processing
		result = try await transformer.transform(result)
		result = try await transformer.transform(result)

		return result
	}
}

//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for URL transformers
public protocol URLTransformer: Sendable {
	func transform(_ url: URL) async throws -> URL
}

/// Default URL transformer that normalizes URLs
public final class URLNormalizationTransformer: URLTransformer {
	public init() {}

	public func transform(_ url: URL) async throws -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
			throw DeepLinkError.invalidURL(url)
		}

		// Normalize path
		components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		if !components.path.isEmpty, !components.path.hasPrefix("/") {
			components.path = "/" + components.path
		}

		// Remove empty query parameters
		components.queryItems = components.queryItems?.filter { $0.value != nil && !$0.value!.isEmpty }

		guard let normalizedURL = components.url else {
			throw DeepLinkError.invalidURL(url)
		}

		return normalizedURL
	}
}
