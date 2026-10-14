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
public protocol DeepLinkMiddleware: _DeepLinkURLIntercepting {
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
	/// 1.x middleware implementing only this form keeps compiling, without a
	/// warning, until 3.0 removes it.
	///
	/// - Parameter url: The deep link URL to intercept
	/// - Returns: The URL to continue processing with, or `nil` to stop processing
	/// - Throws: An error to stop processing and report the issue
	@available(*, deprecated, message: "Implement and call intercept(_: DeepLinkRequest), which keeps the link's context; the URL form is removed in 3.0.")
	func intercept(_ url: URL) async throws -> URL?

	/// Called once the link this middleware intercepted has finished
	/// processing, so the middleware can settle work it started (for example
	/// ``SignedLinkMiddleware`` spends a nonce only when the link succeeded).
	///
	/// ``DeepLinkCoordinator`` calls it for every middleware that ran on the
	/// link in this pass, including one that threw, after routing and the
	/// handler ran; middleware after the one that stopped the chain did not run
	/// and is not called. Middleware before a readiness gate that queued the
	/// link is called with ``DeepLinkOutcome/deferred`` and later once more
	/// with the final outcome. Calling ``DeepLinkMiddlewareCoordinator`` or
	/// `intercept` directly never triggers it. The default does nothing.
	///
	/// - Parameters:
	///   - request: The request this middleware received.
	///   - outcome: How processing ended.
	func didFinish(_ request: DeepLinkRequest, outcome: DeepLinkOutcome) async
}

/// How processing of a deep link ended, as reported to
/// ``DeepLinkMiddleware/didFinish(_:outcome:)``.
public enum DeepLinkOutcome: Sendable {
	/// Routing succeeded and every handler succeeded.
	case succeeded

	/// A middleware returned `nil`, dropping the link.
	case stopped

	/// A ``ReadinessMiddleware`` queued the link; it continues with the
	/// middleware after the readiness gate when the queue drains.
	///
	/// This is not final: the middleware that ran before the gate is called
	/// **again** with the final outcome, when the drained link finishes, or
	/// with ``stopped`` when ``DeepLinkReadinessQueue`` evicts or resets it.
	/// Keep work pending until then (``SignedLinkMiddleware`` keeps its nonce
	/// reserved). A custom ``ReadinessQueue`` that rebuilds requests instead
	/// of storing them loses this settlement; the work then only ends by
	/// whatever expiry it has (a nonce reservation's time to live).
	case deferred

	/// A middleware or the router threw, so no handler ran.
	case failed(any Error)

	/// Routing succeeded and the handlers ran, but at least one threw.
	///
	/// Earlier routes, or the failing handler itself before it threw, may
	/// already have acted, so treat the link as used (``SignedLinkMiddleware``
	/// spends its nonce). Make handlers idempotent where a retry could repeat
	/// a side effect.
	case handlerFailed(any Error)
}

public extension DeepLinkMiddleware {
	/// Does nothing.
	func didFinish(_: DeepLinkRequest, outcome _: DeepLinkOutcome) async {}

	/// Bridges 1.x middleware: runs ``intercept(_:)-(URL)`` on the request's
	/// URL and keeps the request's context.
	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		try await ProtocolBridgeGuard.bridge(Self.self, .intercept, hop: .contextToLegacy) {
			try await Self.legacyIntercept(self, request.url).map(request.replacingURL)
		}
	}

	private static func legacyIntercept(_ middleware: some _DeepLinkURLIntercepting, _ url: URL) async throws -> URL? {
		try await middleware.intercept(url)
	}
}

/// The URL-only interception form of 1.x, which ``DeepLinkMiddleware``
/// refines and deprecates.
///
/// It exists so the library can still call 1.x middleware through the
/// request form without a deprecation warning; do not conform to it or call
/// it directly. It is removed together with the URL form in 3.0.
public protocol _DeepLinkURLIntercepting: Sendable {
	func intercept(_ url: URL) async throws -> URL?
}

public extension _DeepLinkURLIntercepting where Self: DeepLinkMiddleware {
	/// Runs ``DeepLinkMiddleware/intercept(_:)-(DeepLinkRequest)`` with a ``DeepLinkContext/unknown`` context.
	func intercept(_ url: URL) async throws -> URL? {
		try await ProtocolBridgeGuard.bridge(Self.self, .intercept, hop: .legacyToContext) {
			try await intercept(DeepLinkRequest(url: url))?.url
		}
	}
}
