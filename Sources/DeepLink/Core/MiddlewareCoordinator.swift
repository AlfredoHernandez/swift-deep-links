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
/// ## Thread Safety
///
/// This actor provides thread-safe access to middleware operations using Swift's
/// actor isolation model, eliminating data races and ensuring safe concurrent access.
public actor DeepLinkMiddlewareCoordinator {
	private var middleware: [any DeepLinkMiddleware] = []

	/// Creates a new middleware coordinator.
	///
	/// ## Examples
	///
	/// ```swift
	/// let coordinator = DeepLinkMiddlewareCoordinator()
	/// ```
	public init() {}

	/// Adds middleware to the coordinator.
	///
	/// Middleware is executed in the order it's added. The first middleware added
	/// will be the first to intercept URLs.
	///
	/// - Parameter middleware: The middleware to add
	public func add(_ middleware: any DeepLinkMiddleware) {
		self.middleware.append(middleware)
	}

	/// Removes all middleware from the coordinator.
	public func removeAll() {
		middleware.removeAll()
	}

	/// Removes middleware of a specific type.
	///
	/// - Parameter type: The type of middleware to remove
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
	/// - Parameter url: The URL to process
	/// - Returns: The processed URL, or `nil` if processing was stopped
	/// - Throws: An error if any middleware throws an error
	public func process(_ url: URL) async throws -> URL? {
		var currentURL = url

		for middleware in middleware {
			let result = try await middleware.intercept(currentURL)

			// If middleware returns nil, stop processing
			guard let url = result else {
				return nil
			}

			currentURL = url
		}

		return currentURL
	}
}

/// Extension to support advanced middleware
public extension DeepLinkMiddlewareCoordinator {
	/// Adds advanced middleware to the coordinator.
	///
	/// - Parameter middleware: The advanced middleware to add
	func add(_ middleware: any AdvancedDeepLinkMiddleware) {
		add(AdvancedMiddlewareWrapper(middleware))
	}
}

/// Wrapper that converts AdvancedDeepLinkMiddleware to DeepLinkMiddleware
private struct AdvancedMiddlewareWrapper: DeepLinkMiddleware {
	private let advancedMiddleware: any AdvancedDeepLinkMiddleware

	init(_ advancedMiddleware: any AdvancedDeepLinkMiddleware) {
		self.advancedMiddleware = advancedMiddleware
	}

	func intercept(_ url: URL) async throws -> URL? {
		let result = await advancedMiddleware.intercept(url)

		switch result {
		case let .continue(url):
			return url

		case let .transform(url):
			return url

		case let .error(error):
			throw error

		case .handled:
			return nil
		}
	}
}
