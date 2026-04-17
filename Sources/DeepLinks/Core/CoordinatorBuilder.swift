//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A builder for creating and configuring `DeepLinkCoordinator` instances.
///
/// The `DeepLinkCoordinatorBuilder` provides a fluent, immutable API for setting up
/// deep link coordinators with middleware, delegates, and other configuration options.
/// Each configuration method returns a new builder instance, preserving value semantics.
///
/// ## Basic Usage
///
/// ```swift
/// let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(DefaultDeepLinkRouting(parsers: parsers))
///     .handler(appHandler)
///     .middleware(myMiddleware)
///     .delegate(myDelegate)
///     .build()
/// ```
///
/// ## Multiple Middleware and Delegates
///
/// ```swift
/// let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(DefaultDeepLinkRouting(parsers: parsers))
///     .handler(appHandler)
///     .middleware(.security(), .rateLimit(), .logging())
///     .delegate(compose(.logging(), .analytics(provider: provider)))
///     .build()
/// ```
///
/// - Parameter Route: The type of route that the coordinator will handle
public struct DeepLinkCoordinatorBuilder<Route: DeepLinkRoute>: Sendable {
	private var _routing: (any DeepLinkRouting<Route>)?
	private var _handler: (any DeepLinkHandler<Route>)?
	private var _middlewareCoordinator: DeepLinkMiddlewareCoordinator?
	private var middlewareEntries: [MiddlewareEntry] = []
	private var _delegates: [DeepLinkCoordinatorDelegate] = []

	/// Creates a new builder instance.
	public init() {}

	/// Sets the routing implementation for the coordinator.
	///
	/// - Parameter routing: The routing implementation
	/// - Returns: A new builder with the routing configured
	public func routing(_ routing: any DeepLinkRouting<Route>) -> Self {
		var copy = self
		copy._routing = routing
		return copy
	}

	/// Sets the handler implementation for the coordinator.
	///
	/// - Parameter handler: The handler implementation
	/// - Returns: A new builder with the handler configured
	public func handler(_ handler: any DeepLinkHandler<Route>) -> Self {
		var copy = self
		copy._handler = handler
		return copy
	}

	/// Sets a custom middleware coordinator.
	///
	/// - Parameter coordinator: The custom middleware coordinator
	/// - Returns: A new builder with the middleware coordinator configured
	public func middlewareCoordinator(_ coordinator: DeepLinkMiddlewareCoordinator) -> Self {
		var copy = self
		copy._middlewareCoordinator = coordinator
		return copy
	}

	/// Adds one or more middleware to the coordinator.
	///
	/// Middleware is executed in the order it's added.
	///
	/// - Parameter middleware: The middleware to add
	/// - Returns: A new builder with the middleware appended
	public func middleware(_ middleware: any DeepLinkMiddleware...) -> Self {
		var copy = self
		copy.middlewareEntries.append(contentsOf: middleware.map { .standard($0) })
		return copy
	}

	/// Adds an array of middleware to the coordinator.
	///
	/// - Parameter middleware: An array of middleware to add
	/// - Returns: A new builder with the middleware appended
	public func middleware(_ middleware: [any DeepLinkMiddleware]) -> Self {
		var copy = self
		copy.middlewareEntries.append(contentsOf: middleware.map { .standard($0) })
		return copy
	}

	/// Adds one or more advanced middleware to the coordinator.
	///
	/// - Parameter middleware: The advanced middleware to add
	/// - Returns: A new builder with the advanced middleware appended
	public func advancedMiddleware(_ middleware: any AdvancedDeepLinkMiddleware...) -> Self {
		var copy = self
		copy.middlewareEntries.append(contentsOf: middleware.map { .advanced($0) })
		return copy
	}

	/// Adds one or more delegates to the coordinator.
	///
	/// When multiple delegates are configured, they are automatically
	/// composed into a `CompositeDeepLinkDelegate`.
	///
	/// - Parameter delegate: The delegates to add
	/// - Returns: A new builder with the delegates appended
	public func delegate(_ delegate: DeepLinkCoordinatorDelegate...) -> Self {
		var copy = self
		copy._delegates.append(contentsOf: delegate)
		return copy
	}

	/// Adds an array of delegates to the coordinator.
	///
	/// - Parameter delegates: An array of delegates to add
	/// - Returns: A new builder with the delegates appended
	public func delegates(_ delegates: [DeepLinkCoordinatorDelegate]) -> Self {
		var copy = self
		copy._delegates.append(contentsOf: delegates)
		return copy
	}

	/// Builds and returns the configured `DeepLinkCoordinator`.
	///
	/// - Returns: A fully configured `DeepLinkCoordinator` instance
	/// - Throws: `DeepLinkError.missingRequiredConfiguration` if routing or handler are missing
	public func build() async throws -> DeepLinkCoordinator<Route> {
		guard let routing = _routing else {
			throw DeepLinkError.missingRequiredConfiguration("routing")
		}

		guard let handler = _handler else {
			throw DeepLinkError.missingRequiredConfiguration("handler")
		}

		let coordinator = _middlewareCoordinator ?? DeepLinkMiddlewareCoordinator()

		for entry in middlewareEntries {
			switch entry {
			case let .standard(m):
				await coordinator.add(m)

			case let .advanced(m):
				await coordinator.add(m)
			}
		}

		let capturedDelegates = _delegates
		let finalDelegate: (any DeepLinkCoordinatorDelegate)? = if capturedDelegates.count == 1 {
			capturedDelegates.first
		} else if capturedDelegates.count > 1 {
			await MainActor.run {
				CompositeDeepLinkDelegate(delegates: capturedDelegates)
			}
		} else {
			nil
		}

		return DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: coordinator,
			delegate: finalDelegate,
		)
	}
}

// MARK: - Supporting Types

private enum MiddlewareEntry {
	case standard(any DeepLinkMiddleware)
	case advanced(any AdvancedDeepLinkMiddleware)
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
	/// Each delegate is called sequentially in the order provided.
	/// Delegate implementations should be lightweight and non-blocking,
	/// as a slow delegate will delay all subsequent delegates in the chain.
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
