//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for intercepting and processing deep links before they reach parsers.
///
/// Middleware allows you to intercept deep link URLs and perform operations such as:
/// - Analytics tracking
/// - Authentication validation
/// - Rate limiting
/// - Logging
/// - URL transformation
/// - Security validation
///
/// Middleware is executed in the order it's added to the coordinator, and each middleware
/// can either allow the URL to continue to the next middleware/parser, or stop the processing
/// by throwing an error or returning a modified URL.
///
/// ## Usage with Static Factory Methods
///
/// ```swift
/// // Using static factory methods (recommended)
/// coordinator.add(.analytics(provider: myProvider))
/// coordinator.add(.rateLimit(maxRequests: 10, timeWindow: 60))
/// coordinator.add(.security(allowedSchemes: ["https", "myapp"]))
/// coordinator.add(.logging(format: .detailed))
/// ```
///
/// ## Custom Implementation
///
/// Implement ``intercept(_:)-(DeepLinkRequest)`` to see where the link came
/// from through its ``DeepLinkContext``:
///
/// ```swift
/// struct UniversalLinksOnlyForPayments: DeepLinkMiddleware {
///     func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
///         if request.url.path().hasPrefix("/pay"), request.context.source != .universalLink {
///             throw DeepLinkError.securityViolation("Payments require a Universal Link")
///         }
///         return request
///     }
/// }
/// ```
///
/// ## Migrating 1.x Middleware
///
/// Implement exactly one of the two `intercept` methods; each has a default
/// that calls the other, and a type implementing neither throws
/// ``DeepLinkError/missingRequiredConfiguration(_:)`` when called.
/// The URL form, `intercept(_ url: URL)`, is **deprecated** and will be
/// removed in 3.0: it still compiles and runs, bridged so the request keeps
/// its context, but it cannot read the context. Replace
///
/// ```swift
/// func intercept(_ url: URL) async throws -> URL? { … return url }
/// ```
///
/// with
///
/// ```swift
/// func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? { … return request }
/// ```
public protocol DeepLinkMiddleware: Sendable {
	/// Intercepts a deep link before it reaches the parsers.
	///
	/// - Parameter request: The URL being processed and the context it arrived with
	/// - Returns: The request to continue with (use ``DeepLinkRequest/replacingURL(_:)``
	///   to rewrite the URL), or `nil` to stop processing
	/// - Throws: An error to stop processing and report the issue
	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest?

	/// Intercepts a deep link URL before it reaches the parsers.
	///
	/// Deprecated in 2.0: implement ``intercept(_:)-(DeepLinkRequest)`` instead.
	/// Calling this form runs the middleware with a ``DeepLinkContext/unknown`` context.
	///
	/// - Parameter url: The deep link URL to intercept
	/// - Returns: The URL to continue processing with, or `nil` to stop processing
	/// - Throws: An error to stop processing and report the issue
	func intercept(_ url: URL) async throws -> URL?
}

public extension DeepLinkMiddleware {
	/// Bridges 1.x middleware: runs ``intercept(_:)-(URL)`` on the request's
	/// URL and keeps the request's context.
	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		try await ProtocolBridgeGuard.bridge(Self.self, .intercept, hop: .contextToLegacy) {
			try await intercept(request.url).map(request.replacingURL)
		}
	}

	/// Runs ``intercept(_:)-(DeepLinkRequest)`` with a ``DeepLinkContext/unknown`` context.
	func intercept(_ url: URL) async throws -> URL? {
		try await ProtocolBridgeGuard.bridge(Self.self, .intercept, hop: .legacyToContext) {
			try await intercept(DeepLinkRequest(url: url))?.url
		}
	}
}
