//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// A builder for creating and configuring `DeepLinkCoordinator` instances.
///
/// The `DeepLinkCoordinatorBuilder` provides a fluent, immutable API for setting up
/// deep link coordinators with middleware, delegates, and other configuration options.
/// Each configuration method returns a new builder instance, preserving value semantics.
///
/// ## Basic Usage
///
/// ```swift
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(DefaultDeepLinkRouting(parsers: parsers))
///     .handler(appHandler)
///     .middleware(myMiddleware)
///     .delegate(myDelegate)
///     .build()
/// ```
///
/// ## Shorter Style Using Parser And Handler Factories
///
/// ```swift
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .parser(MyParser())
///     .handler(.from { route in await navigate(route) })
///     .build()
/// ```
///
/// ## Multiple Middleware and Delegates
///
/// ```swift
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
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
	private var middlewareEntries: [any DeepLinkMiddleware] = []
	private var _delegates: [any DeepLinkCoordinatorDelegate<Route>] = []
	private var _routeExecutionDelay: Duration = .zero
	private var _sleep: (@Sendable (Duration) async -> Void)?
	private var _logPrivacy = DeepLinkLogPrivacy.redacted
	private var _diagnosticLog = LoggingProvider.systemLogger(Logger(subsystem: "swift-deep-links", category: "DeepLinkCoordinatorBuilder"))
	var presetMiddleware: [any DeepLinkMiddleware] = []

	/// Creates a new builder instance.
	public init() {}

	/// Sets the routing implementation for the coordinator.
	///
	/// ``routing(_:)`` shares storage with ``parser(_:)`` and ``parsers(_:)``.
	/// Calling them together is last-one-wins: the final call decides which
	/// routing implementation is used when ``build()`` runs.
	///
	/// - Parameter routing: The routing implementation
	/// - Returns: A new builder with the routing configured
	public func routing(_ routing: any DeepLinkRouting<Route>) -> Self {
		var copy = self
		copy._routing = routing
		return copy
	}

	/// Sets the routing implementation to a ``DefaultDeepLinkRouting`` backed
	/// by the supplied parser.
	///
	/// Use this shortcut when you don't need a custom routing implementation;
	/// it wraps the parser in ``DefaultDeepLinkRouting`` and stores it as the
	/// builder's routing.
	///
	/// ``parser(_:)`` and ``parsers(_:)`` share storage with ``routing(_:)``.
	/// Calling them together is last-one-wins: the final call decides which
	/// routing implementation is used when ``build()`` runs.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(MyParser())
	///     .handler(.from { route in await navigate(route) })
	///     .build()
	/// ```
	///
	/// - Parameter parser: A parser used to route URLs into `Route` values.
	/// - Returns: A new builder whose routing wraps the supplied parser.
	public func parser(_ parser: any DeepLinkParser<Route>) -> Self {
		parsers([parser])
	}

	/// Sets the routing implementation to a ``DefaultDeepLinkRouting`` backed
	/// by the supplied parsers.
	///
	/// Parsers are tried in order; the first one to succeed decides the
	/// route. This mirrors the behaviour of ``DefaultDeepLinkRouting``.
	///
	/// ``parser(_:)`` and ``parsers(_:)`` share storage with ``routing(_:)``.
	/// Calling them together is last-one-wins: the final call decides which
	/// routing implementation is used when ``build()`` runs.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parsers([UserParser(), ProductParser()])
	///     .handler(.from { route in await navigate(route) })
	///     .build()
	/// ```
	///
	/// - Parameter parsers: Parsers tried in order when routing URLs.
	/// - Returns: A new builder whose routing wraps the supplied parsers.
	public func parsers(_ parsers: [any DeepLinkParser<Route>]) -> Self {
		var copy = self
		copy._routing = DefaultDeepLinkRouting(parsers: parsers)
		return copy
	}

	/// Variadic convenience for ``parsers(_:)``.
	///
	/// The signature requires at least one leading parser so that
	/// `.parsers()` with no arguments is rejected at compile time — an empty
	/// parser list would produce a coordinator that silently fails every URL
	/// with ``DeepLinkError/routeNotFound(_:)``. If you genuinely need a
	/// deferred configuration (zero parsers now, overridden later via
	/// ``routing(_:)``), use the array overload with an explicit empty array
	/// instead.
	///
	/// ``parser(_:)`` and ``parsers(_:)`` share storage with ``routing(_:)``.
	/// Calling them together is last-one-wins: the final call decides which
	/// routing implementation is used when ``build()`` runs.
	///
	/// ## Example
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parsers(UserParser(), ProductParser())
	///     .handler(.from { route in await navigate(route) })
	///     .build()
	/// ```
	///
	/// - Parameters:
	///   - first: The leading parser. Required so the call has at least one parser.
	///   - rest: Additional parsers tried after `first`, in order.
	/// - Returns: A new builder whose routing wraps the supplied parsers.
	public func parsers(
		_ first: any DeepLinkParser<Route>,
		_ rest: any DeepLinkParser<Route>...,
	) -> Self {
		parsers([first] + rest)
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
		copy.middlewareEntries.append(contentsOf: middleware)
		return copy
	}

	/// Adds an array of middleware to the coordinator.
	///
	/// - Parameter middleware: An array of middleware to add
	/// - Returns: A new builder with the middleware appended
	public func middleware(_ middleware: [any DeepLinkMiddleware]) -> Self {
		var copy = self
		copy.middlewareEntries.append(contentsOf: middleware)
		return copy
	}

	/// Adds one or more delegates to the coordinator.
	///
	/// When multiple delegates are configured, they are automatically
	/// composed into a `CompositeDeepLinkDelegate`.
	///
	/// - Parameter delegate: The delegates to add
	/// - Returns: A new builder with the delegates appended
	public func delegate(_ delegate: any DeepLinkCoordinatorDelegate<Route>...) -> Self {
		var copy = self
		copy._delegates.append(contentsOf: delegate)
		return copy
	}

	/// Adds an array of delegates to the coordinator.
	///
	/// - Parameter delegates: An array of delegates to add
	/// - Returns: A new builder with the delegates appended
	public func delegates(_ delegates: [any DeepLinkCoordinatorDelegate<Route>]) -> Self {
		var copy = self
		copy._delegates.append(contentsOf: delegates)
		return copy
	}

	/// Sets the delay inserted between consecutive route-handler executions.
	///
	/// Defaults to `.zero`; pass a positive ``Duration`` when a stack of
	/// routes would otherwise trigger jarring, rapid navigation updates.
	///
	/// - Parameter delay: The inter-route delay to apply during
	///   ``DeepLinkCoordinator/handle(url:)``.
	/// - Returns: A new builder with the delay configured.
	public func routeExecutionDelay(_ delay: Duration) -> Self {
		var copy = self
		copy._routeExecutionDelay = delay
		return copy
	}

	/// Overrides the coordinator's sleep primitive used between route
	/// executions when ``routeExecutionDelay(_:)`` is positive.
	///
	/// Intended as a test seam: pass a closure that records the requested
	/// ``Duration`` or returns immediately so time-dependent assertions can
	/// run without real wall-clock delays. In production, leave this
	/// unconfigured — the coordinator's default is `Task.sleep(for:)`.
	///
	/// - Parameter sleep: A closure invoked with the configured
	///   ``routeExecutionDelay(_:)`` before each non-terminal route executes.
	/// - Returns: A new builder with the sleep primitive configured.
	public func sleep(_ sleep: @Sendable @escaping (Duration) async -> Void) -> Self {
		var copy = self
		copy._sleep = sleep
		return copy
	}

	/// Sets how the coordinator's error logs describe URLs and errors.
	///
	/// Defaults to ``DeepLinkLogPrivacy/redacted``. It does not affect
	/// routing built by ``parser(_:)`` or ``parsers(_:)-(Array)``, which also
	/// redact by default; pass a ``DefaultDeepLinkRouting`` with its own
	/// `logPrivacy` to ``routing(_:)`` to change those.
	///
	/// - Parameter privacy: The privacy setting, for example ``DeepLinkLogPrivacy/unredacted`` while debugging.
	/// - Returns: A new builder with the privacy configured.
	public func logPrivacy(_ privacy: DeepLinkLogPrivacy) -> Self {
		var copy = self
		copy._logPrivacy = privacy
		return copy
	}

	/// Replaces where debug-build configuration warnings go; a test seam.
	func diagnosticLog(_ log: LoggingProvider) -> Self {
		var copy = self
		copy._diagnosticLog = log
		return copy
	}

	/// Builds and returns the configured `DeepLinkCoordinator`.
	///
	/// This method assembles all configured components into a functional coordinator
	/// ready for deep link processing. It validates that all required components
	/// (routing and handler) have been configured.
	///
	/// ## Configuration Validation
	///
	/// The builder ensures:
	/// - Routing implementation is configured (required)
	/// - Handler implementation is configured (required)
	/// - Middleware is added in the correct order
	/// - Multiple delegates are automatically composed
	///
	/// In debug builds, a chain without a ``SecurityMiddleware`` (added
	/// directly or by `secureDefaults(allowedSchemes:)`) logs a warning;
	/// behavior is unchanged. A custom
	/// ``middlewareCoordinator(_:)`` is not inspected.
	///
	/// ## Examples
	///
	/// ```swift
	/// // Basic usage
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .routing(routing)
	///     .handler(handler)
	///     .build()
	///
	/// // With middleware and delegates
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .routing(routing)
	///     .handler(handler)
	///     .middleware(.security(allowedSchemes: ["myapp"]))
	///     .middleware(.logging())
	///     .delegate(.analytics(provider: myProvider))
	///     .delegate(.logging())
	///     .build()
	/// ```
	///
	/// - Returns: A fully configured `DeepLinkCoordinator` instance ready for use
	/// - Throws: `DeepLinkError.missingRequiredConfiguration` if routing or handler are missing
	public func build() throws -> DeepLinkCoordinator<Route> {
		guard let routing = _routing else {
			throw DeepLinkError.missingRequiredConfiguration("routing")
		}

		guard let handler = _handler else {
			throw DeepLinkError.missingRequiredConfiguration("handler")
		}

		let chain = presetMiddleware + middlewareEntries
		let coordinator: DeepLinkMiddlewareCoordinator
		if let custom = _middlewareCoordinator {
			guard chain.isEmpty else {
				throw DeepLinkError.missingRequiredConfiguration(
					"Cannot combine a custom middlewareCoordinator with additional middleware entries; register middleware on the coordinator before passing it to the builder.",
				)
			}
			coordinator = custom
		} else {
			#if DEBUG
			warnIfUnprotected(chain)
			#endif
			coordinator = DeepLinkMiddlewareCoordinator(middleware: chain)
		}

		let capturedDelegates = _delegates
		let finalDelegate: (any DeepLinkCoordinatorDelegate<Route>)? = if capturedDelegates.count == 1 {
			capturedDelegates.first
		} else if capturedDelegates.count > 1 {
			CompositeDeepLinkDelegate<Route>(delegates: capturedDelegates)
		} else {
			nil
		}

		let defaultSleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
		return DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: coordinator,
			routeExecutionDelay: _routeExecutionDelay,
			delegate: finalDelegate,
			sleep: _sleep ?? defaultSleep,
			logPrivacy: _logPrivacy,
		)
	}
}

// MARK: - Diagnostics

private extension DeepLinkCoordinatorBuilder {
	func warnIfUnprotected(_ chain: [any DeepLinkMiddleware]) {
		guard !chain.contains(where: { $0 is SecurityMiddleware }) else { return }
		_diagnosticLog.log(
			level: .error,
			"No SecurityMiddleware is registered: every scheme, host and source reaches your parsers. Add .secureDefaults(allowedSchemes:) or .middleware(.security(allowedSchemes:)) first in the chain.",
		)
	}
}

// MARK: - Supporting Types

/// A composite delegate that combines multiple `DeepLinkCoordinatorDelegate` implementations.
///
/// This class is used internally by the builder when multiple delegates are provided.
/// It can also be created directly using the `compose` function.
///
/// Thread safety is guaranteed by making the delegates array immutable after initialization.
/// The array is set once during init and never modified, making it safe for concurrent access.
@MainActor
public final class CompositeDeepLinkDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
	private let delegates: [any DeepLinkCoordinatorDelegate<Route>]

	/// Creates a composite delegate with the provided delegates.
	///
	/// Each delegate is called sequentially in the order provided.
	/// Delegate implementations should be lightweight and non-blocking,
	/// as a slow delegate will delay all subsequent delegates in the chain.
	///
	/// This initializer is `nonisolated` because it only captures an
	/// immutable array; no `@MainActor`-isolated state is touched.
	///
	/// - Parameter delegates: Array of delegates to combine
	public nonisolated init(delegates: [any DeepLinkCoordinatorDelegate<Route>]) {
		self.delegates = delegates
	}

	/// Called before the coordinator begins processing a deep link URL.
	///
	/// This method forwards the call to all contained delegates in sequence.
	///
	/// - Parameters:
	///   - coordinator: The coordinator that will process the URL
	///   - url: The deep link URL that will be processed
	public func coordinator(_ coordinator: DeepLinkCoordinator<Route>, willProcess url: URL) {
		for delegate in delegates {
			delegate.coordinator(coordinator, willProcess: url)
		}
	}

	/// Called after the coordinator processes a deep link URL.
	///
	/// This method forwards the call to all contained delegates in sequence.
	///
	/// - Parameters:
	///   - coordinator: The coordinator that processed the URL
	///   - url: The deep link URL that was processed
	///   - result: The result of the processing operation
	public func coordinator(_ coordinator: DeepLinkCoordinator<Route>, didProcess url: URL, result: DeepLinkResult<Route>) {
		for delegate in delegates {
			delegate.coordinator(coordinator, didProcess: url, result: result)
		}
	}

	/// Called when the coordinator fails to process a deep link URL.
	///
	/// This method forwards the call to all contained delegates in sequence.
	///
	/// - Parameters:
	///   - coordinator: The coordinator that failed to process the URL
	///   - url: The deep link URL that failed to process
	///   - error: The error that caused the processing to fail
	public func coordinator(_ coordinator: DeepLinkCoordinator<Route>, didFailProcessing url: URL, error: Error) {
		for delegate in delegates {
			delegate.coordinator(coordinator, didFailProcessing: url, error: error)
		}
	}
}
