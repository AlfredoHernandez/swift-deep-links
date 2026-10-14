//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Coordinates the execution of middleware in sequence.
///
/// The middleware coordinator executes middleware in the order they were added,
/// allowing each middleware to intercept, transform, or stop the processing of
/// deep link URLs before they reach the parsers.
///
/// ## Execution Order
///
/// **Middleware order matters.** Each middleware receives the URL produced by the
/// previous one. A middleware can stop the chain at any point by returning `nil`
/// or throwing an error. Place middleware that should run first (e.g., security,
/// rate limiting) before middleware that depends on a validated URL (e.g., analytics,
/// logging).
///
/// Recommended order:
/// 1. **Security** — reject disallowed schemes/hosts early
/// 2. **Rate limiting** — prevent abuse before doing further work
/// 3. **Authentication** — verify access for protected routes
/// 4. **URL transformation** — normalize the URL
/// 5. **Analytics** — track the (validated) deep link
/// 6. **Logging** — log the final processed request
///
/// ## Usage Example
///
/// ```swift
/// let coordinator = DeepLinkMiddlewareCoordinator()
/// await coordinator.add(.security(allowedSchemes: ["myapp"]))
/// await coordinator.add(.rateLimit(maxRequests: 10, timeWindow: 60))
/// await coordinator.add(.authentication(provider: authProvider))
/// await coordinator.add(.logging())
///
/// let processedURL = try await coordinator.process(url)
/// ```
///
/// ## Instruments
///
/// Each middleware call is wrapped in an `os_signpost` interval named
/// `Middleware` (subsystem `swift-deep-links`, category `Middleware`) and
/// labelled with the middleware's type name; URLs are never logged. Use the
/// Points of Interest or os_signpost instrument to see where link time goes.
///
/// ## Thread Safety
///
/// This actor provides thread-safe access to middleware operations using Swift's
/// actor isolation model, eliminating data races and ensuring safe concurrent access.
public actor DeepLinkMiddlewareCoordinator {
	private var middleware: [any DeepLinkMiddleware] = []
	private let tracing: any MiddlewareIntervalTracing

	/// Creates a new middleware coordinator.
	///
	/// ## Examples
	///
	/// ```swift
	/// let coordinator = DeepLinkMiddlewareCoordinator()
	/// ```
	public init() {
		tracing = SignpostMiddlewareTracing()
	}

	/// Creates a new middleware coordinator pre-populated with the supplied
	/// middleware in the given order.
	///
	/// This synchronous initializer is equivalent to creating an empty
	/// coordinator and calling ``add(_:)`` for each middleware, but avoids the
	/// actor-hop loop entirely.
	///
	/// - Parameter middleware: Middleware to register, executed in the order
	///   supplied.
	public init(middleware: [any DeepLinkMiddleware]) {
		self.init(middleware: middleware, tracing: SignpostMiddlewareTracing())
	}

	init(middleware: [any DeepLinkMiddleware], tracing: any MiddlewareIntervalTracing) {
		self.middleware = middleware
		self.tracing = tracing
	}

	/// Adds middleware to the coordinator.
	///
	/// Middleware is executed in the order it's added. The first middleware added
	/// will be the first to intercept URLs. Each middleware can modify, stop, or
	/// allow the URL to continue through the chain.
	///
	/// ## Middleware Order Matters
	///
	/// The order in which middleware is added determines its execution order:
	/// 1. Security middleware (reject invalid schemes/hosts early)
	/// 2. Rate limiting (prevent abuse)
	/// 3. Authentication (verify access)
	/// 4. URL transformation (normalize URLs)
	/// 5. Analytics/Logging (track validated URLs)
	///
	/// - Parameter middleware: The middleware to add
	/// - Complexity: O(1) amortized
	public func add(_ middleware: any DeepLinkMiddleware) {
		self.middleware.append(middleware)
	}

	/// Removes all middleware from the coordinator.
	///
	/// After calling this method, the coordinator will process URLs without
	/// any middleware interception, routing directly to the parsers.
	///
	/// - Complexity: O(n) where n is the number of middleware instances
	public func removeAll() {
		middleware.removeAll()
	}

	/// Removes all middleware of a specific type.
	///
	/// This method removes all instances of the specified middleware type from the
	/// coordinator. If no middleware of that type is found, this method does nothing.
	///
	/// ## Example
	///
	/// ```swift
	/// // Remove all rate limiting middleware
	/// await coordinator.removeMiddleware(RateLimitMiddleware.self)
	/// ```
	///
	/// - Parameter type: The type of middleware to remove
	/// - Complexity: O(n) where n is the number of middleware instances
	public func remove<T: DeepLinkMiddleware>(_: T.Type) {
		middleware.removeAll { $0 is T }
	}

	/// Processes a URL through all middleware in sequence.
	///
	/// Each middleware can:
	/// - Return the original URL to continue processing
	/// - Return a modified URL to transform the request
	/// - Return `nil` to stop processing
	/// - Throw an error to stop processing with an error
	///
	/// The URL runs with a ``DeepLinkContext/unknown`` context; use
	/// ``process(_:)-(DeepLinkRequest)`` to supply one.
	///
	/// - Parameter url: The URL to process
	/// - Returns: The processed URL, or `nil` if processing was stopped
	/// - Throws: An error if any middleware throws an error
	public func process(_ url: URL) async throws -> URL? {
		try await process(DeepLinkRequest(url: url))?.url
	}

	/// Processes a request through all middleware in sequence.
	///
	/// - Parameter request: The URL and the context it arrived with
	/// - Returns: The processed request, or `nil` if processing was stopped
	/// - Throws: An error if any middleware throws an error
	public func process(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		try await run(request, through: middleware[...])
	}

	/// Processes a URL through the middleware registered after `anchor`,
	/// resuming a chain that `anchor` previously paused.
	///
	/// Middleware up to and including `anchor` is skipped, because it already
	/// ran when the URL was first intercepted. The anchor is matched by object
	/// identity; if it is not registered, the URL runs through the entire
	/// chain so a missing anchor never skips security checks.
	///
	/// ## Example
	///
	/// ```swift
	/// let readiness = ReadinessMiddleware(queue: queue)
	/// let coordinator = DeepLinkMiddlewareCoordinator(middleware: [readiness, .authentication(provider: auth)])
	///
	/// for url in queue.markReady() {
	///     let processedURL = try await coordinator.process(url, startingAfter: readiness)
	/// }
	/// ```
	///
	/// - Parameters:
	///   - url: The URL to process
	///   - anchor: The registered middleware after which processing resumes
	/// - Returns: The processed URL, or `nil` if processing was stopped
	/// - Throws: An error if any of the remaining middleware throws an error
	public func process(_ url: URL, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> URL? {
		try await process(DeepLinkRequest(url: url), startingAfter: anchor)?.url
	}

	/// Processes a request through the middleware registered after `anchor`.
	/// See ``process(_:startingAfter:)-(URL,_)``.
	public func process(_ request: DeepLinkRequest, startingAfter anchor: some DeepLinkMiddleware & AnyObject) async throws -> DeepLinkRequest? {
		try await run(request, through: middleware(after: { ($0 as AnyObject) === anchor }))
	}

	func process(_ request: DeepLinkRequest, resumingAfterReadinessOf queue: any ReadinessQueue) async throws -> DeepLinkRequest? {
		let remaining = middleware(after: { candidate in
			guard let readiness = candidate as? ReadinessMiddleware else { return false }
			return readiness.isGating(queue)
		})
		return try await run(request, through: remaining)
	}
}

// MARK: - Chain Execution

private extension DeepLinkMiddlewareCoordinator {
	func middleware(after isAnchor: (any DeepLinkMiddleware) -> Bool) -> ArraySlice<any DeepLinkMiddleware> {
		guard let anchorIndex = middleware.firstIndex(where: isAnchor) else {
			return middleware[...]
		}
		return middleware[(anchorIndex + 1)...]
	}

	func run(_ request: DeepLinkRequest, through chain: ArraySlice<any DeepLinkMiddleware>) async throws -> DeepLinkRequest? {
		var current = request

		for middleware in chain {
			guard let next = try await intercept(current, with: middleware) else {
				return nil
			}

			current = next
		}

		return current
	}

	func intercept(_ request: DeepLinkRequest, with middleware: any DeepLinkMiddleware) async throws -> DeepLinkRequest? {
		let interval = tracing.beginInterval(named: String(describing: type(of: middleware)))
		defer { interval.end() }
		return try await middleware.intercept(request)
	}
}
