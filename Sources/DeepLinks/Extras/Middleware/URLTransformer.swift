//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A protocol that defines how to transform deep link URLs.
///
/// The `URLTransformer` protocol is responsible for transforming URLs before they reach
/// the parsers. This enables URL normalization, parameter injection, redirection of legacy URLs,
/// and other URL modification scenarios.
///
/// ## Usage
///
/// Implement this protocol to define custom URL transformations:
///
/// ```swift
/// final class LegacyURLTransformer: URLTransformer {
///     func transform(_ url: URL) throws -> URL {
///         // Handle legacy URL schemes
///         if url.scheme == "oldapp" {
///             var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
///             components.scheme = "newapp"
///             return components.url!
///         }
///         return url
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations must conform to `Sendable` and be thread-safe, as they may be called
/// from different threads or actors.
///
/// - SeeAlso: ``URLTransformationMiddleware`` for using transformers in the middleware stack
/// - SeeAlso: ``URLNormalizationTransformer`` for a built-in normalization implementation
public protocol URLTransformer: Sendable {
	/// Transforms a deep link URL.
	///
	/// This method should transform the provided URL and return the modified version.
	/// The transformation should be idempotent when possible, and may involve:
	/// - Normalizing URL components
	/// - Converting legacy URL schemes to new ones
	/// - Injecting or removing parameters
	/// - Redirecting to canonical URLs
	///
	/// - Parameter url: The URL to transform
	/// - Returns: The transformed URL
	/// - Throws: An error if the transformation fails (e.g., invalid URL structure)
	func transform(_ url: URL) throws -> URL
}
