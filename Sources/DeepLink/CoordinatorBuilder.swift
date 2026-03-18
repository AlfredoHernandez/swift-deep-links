//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A builder for creating and configuring `DeepLinkCoordinator` instances.
///
/// The `DeepLinkCoordinatorBuilder` provides a fluent API for setting up deep link coordinators
/// with middleware, delegates, and other configuration options. This makes it easier to create
/// complex coordinator configurations without having to manually manage all the setup steps.
///
/// ## Basic Usage
///
/// ```swift
/// let coordinator = DeepLinkCoordinatorBuilder<AppRoute>()
///     .addingRouting(DefaultDeepLinkRouting(parsers: parsers))
///     .addingHandler(AppDeepLinkHandler(navigationRouter: router))
///     .addingMiddleware(AnalyticsMiddleware(analyticsProvider: provider))
///     .addingMiddleware(AuthenticationMiddleware(authProvider: authProvider, protectedHosts: []))
///     .addingDelegate(DeepLinkLoggingDelegate())
///     .addingDelegate(DeepLinkAnalyticsDelegate(analyticsProvider: provider))
///     .build()
/// ```
///
/// ## Usage with Static Factory Methods
///
/// ```swift
/// let coordinator = DeepLinkCoordinatorBuilder<AppRoute>()
///     .addingRouting(DefaultDeepLinkRouting(parsers: parsers))
///     .addingHandler(AppDeepLinkHandler(navigationRouter: router))
///     .addingMiddleware(.analytics(provider: myProvider, strategy: .detailed))
///     .addingMiddleware(.rateLimit(maxRequests: 10, timeWindow: 60))
///     .addingMiddleware(.security(allowedSchemes: ["https", "myapp"]))
///     .addingDelegate(.logging(enableDebugLogging: true))
///     .build()
/// ```
///
/// ## Advanced Usage with Arrays
///
/// ```swift
/// let middleware: [any DeepLinkMiddleware] = [
///     .rateLimit(maxRequests: 10, timeWindow: 60.0),
///     .security(allowedSchemes: ["myapp"], allowedHosts: ["secure.myapp.com"]),
///     .analytics(provider: provider, strategy: .performance)
/// ]
///
/// let delegates: [DeepLinkCoordinatorDelegate] = [
///     .logging(enableDebugLogging: false),
///     .analytics(provider: provider)
/// ]
///
/// let coordinator = DeepLinkCoordinatorBuilder<AppRoute>()
///     .addingRouting(DefaultDeepLinkRouting(parsers: parsers))
///     .addingHandler(AppDeepLinkHandler(navigationRouter: router))
///     .addingMiddleware(middleware)
///     .addingDelegates(delegates)
///     .build()
/// ```
///
/// ## Functional Composition Style
///
/// ```swift
/// let coordinator = DeepLinkCoordinatorBuilder<AppRoute>()
///     .addingRouting(DefaultDeepLinkRouting(parsers: parsers))
///     .addingHandler(AppDeepLinkHandler(navigationRouter: router))
///     .addingMiddleware(compose(
///         .analytics(provider: provider, strategy: .detailed),
///         .rateLimit(maxRequests: 10, timeWindow: 60),
///         .security(allowedSchemes: ["https", "myapp"])
///     ))
///     .addingDelegate(compose(
///         .logging(enableDebugLogging: true),
///         .analytics(provider: provider)
///     ))
///     .build()
/// ```
///
/// - Parameter Route: The type of route that the coordinator will handle
public final class DeepLinkCoordinatorBuilder<Route: DeepLinkRoute>: @unchecked Sendable {
	private var routing: (any DeepLinkRouting<Route>)?
	private var handler: (any DeepLinkHandler<Route>)?
	private var middlewareCoordinator: DeepLinkMiddlewareCoordinator?
	private var middleware: [any DeepLinkMiddleware] = []
	private var delegates: [DeepLinkCoordinatorDelegate] = []

	/// Creates a new builder instance.
	public init() {}

	/// Sets the routing implementation for the coordinator.
	///
	/// - Parameter routing: The routing implementation
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingRouting(_ routing: any DeepLinkRouting<Route>) -> Self {
		self.routing = routing
		return self
	}

	/// Sets the handler implementation for the coordinator.
	///
	/// - Parameter handler: The handler implementation
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingHandler(_ handler: any DeepLinkHandler<Route>) -> Self {
		self.handler = handler
		return self
	}

	/// Sets a custom middleware coordinator for the coordinator.
	///
	/// - Parameter coordinator: The custom middleware coordinator
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingCustomMiddlewareCoordinator(_ coordinator: DeepLinkMiddlewareCoordinator) -> Self {
		middlewareCoordinator = coordinator
		return self
	}

	/// Adds middleware to the coordinator.
	///
	/// - Parameter middleware: The middleware to add
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingMiddleware(_ middleware: any DeepLinkMiddleware) -> Self {
		self.middleware.append(middleware)
		return self
	}

	/// Adds middleware using a closure for lazy initialization.
	///
	/// - Parameter middlewareFactory: A closure that creates the middleware
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingMiddleware(_ middlewareFactory: () -> any DeepLinkMiddleware) -> Self {
		middleware.append(middlewareFactory())
		return self
	}

	/// Adds advanced middleware to the coordinator.
	///
	/// - Parameter middleware: The advanced middleware to add
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingAdvancedMiddleware(_ middleware: any AdvancedDeepLinkMiddleware) -> Self {
		// Store as Any to handle the type conversion later
		self.middleware.append(AnyMiddleware(middleware))
		return self
	}

	/// Adds advanced middleware using a closure for lazy initialization.
	///
	/// - Parameter middlewareFactory: A closure that creates the advanced middleware
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingAdvancedMiddleware(_ middlewareFactory: () -> any AdvancedDeepLinkMiddleware) -> Self {
		// Store as Any to handle the type conversion later
		middleware.append(AnyMiddleware(middlewareFactory()))
		return self
	}

	/// Adds a delegate to the coordinator.
	///
	/// - Parameter delegate: The delegate to add
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingDelegate(_ delegate: DeepLinkCoordinatorDelegate) -> Self {
		delegates.append(delegate)
		return self
	}

	/// Adds a delegate using a closure for lazy initialization.
	///
	/// - Parameter delegateFactory: A closure that creates the delegate
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingDelegate(_ delegateFactory: () -> DeepLinkCoordinatorDelegate) -> Self {
		delegates.append(delegateFactory())
		return self
	}

	/// Adds multiple middleware at once.
	///
	/// - Parameter middleware: An array of middleware to add
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingMiddleware(_ middleware: [any DeepLinkMiddleware]) -> Self {
		self.middleware.append(contentsOf: middleware)
		return self
	}

	/// Adds multiple delegates at once.
	///
	/// - Parameter delegates: An array of delegates to add
	/// - Returns: The builder instance for method chaining
	@discardableResult
	public func addingDelegates(_ delegates: [DeepLinkCoordinatorDelegate]) -> Self {
		self.delegates.append(contentsOf: delegates)
		return self
	}

	/// Builds and returns the configured `DeepLinkCoordinator`.
	///
	/// - Returns: A fully configured `DeepLinkCoordinator` instance
	/// - Throws: `DeepLinkError.missingRequiredConfiguration` if required components are missing
	public func build() async throws -> DeepLinkCoordinator<Route> {
		// Validate required components
		guard let routing else {
			throw DeepLinkError.missingRequiredConfiguration("routing")
		}

		guard let handler else {
			throw DeepLinkError.missingRequiredConfiguration("handler")
		}

		// Create middleware coordinator if not provided
		let coordinator = middlewareCoordinator ?? DeepLinkMiddlewareCoordinator()

		// Add all middleware
		for middleware in middleware {
			if let anyMiddleware = middleware as? AnyMiddleware {
				await coordinator.add(anyMiddleware.advancedMiddleware)
			} else {
				await coordinator.add(middleware)
			}
		}

		// Determine the delegate to use
		let capturedDelegates = delegates
		let finalDelegate: (any DeepLinkCoordinatorDelegate)? = if capturedDelegates.count == 1 {
			capturedDelegates.first
		} else if capturedDelegates.count > 1 {
			await MainActor.run {
				CompositeDeepLinkDelegate(delegates: capturedDelegates)
			}
		} else {
			nil
		}

		// Create the deep link coordinator with all components
		return DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: coordinator,
			delegate: finalDelegate,
		)
	}
}

// MARK: - Helper Classes

/// A wrapper for advanced middleware to handle type conversion.
private final class AnyMiddleware: DeepLinkMiddleware {
	let advancedMiddleware: any AdvancedDeepLinkMiddleware

	init(_ middleware: any AdvancedDeepLinkMiddleware) {
		advancedMiddleware = middleware
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

/// A composite delegate that combines multiple `DeepLinkCoordinatorDelegate` implementations.
///
/// This class is used internally by the builder when multiple delegates are provided.
/// It can also be created directly using the `compose` function.
///
/// Thread safety is guaranteed by making the delegates array immutable after initialization.
/// The array is set once during init and never modified, making it safe for concurrent access.
public final class CompositeDeepLinkDelegate: DeepLinkCoordinatorDelegate {
	private let delegates: [DeepLinkCoordinatorDelegate]

	/// Creates a composite delegate with the provided delegates.
	///
	/// - Parameter delegates: Array of delegates to combine
	public init(delegates: [DeepLinkCoordinatorDelegate]) {
		self.delegates = delegates
	}

	public func coordinator(_ coordinator: AnyObject, willProcess url: URL) {
		for delegate in delegates {
			delegate.coordinator(coordinator, willProcess: url)
		}
	}

	public func coordinator(_ coordinator: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol) {
		for delegate in delegates {
			delegate.coordinator(coordinator, didProcess: url, result: result)
		}
	}

	public func coordinator(_ coordinator: AnyObject, didFailProcessing url: URL, error: Error) {
		for delegate in delegates {
			delegate.coordinator(coordinator, didFailProcessing: url, error: error)
		}
	}
}
