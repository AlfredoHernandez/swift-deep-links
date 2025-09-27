//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
