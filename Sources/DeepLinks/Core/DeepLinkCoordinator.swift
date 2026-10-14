//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import OSLog

/// The main coordinator responsible for orchestrating the deep link handling flow.
///
/// The `DeepLinkCoordinator` acts as the central component that coordinates between
/// the middleware system, routing system, and handler system. It takes a URL, processes
/// it through middleware, routes it through the provided routing implementation, and then
/// executes the appropriate handlers for each resulting route.
///
/// ## Usage
///
/// ```swift
/// // Basic usage with default configuration
/// let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
/// await coordinator.add(myMiddleware)
/// await coordinator.handle(url: deepLinkURL)
///
/// // Advanced usage with custom configuration
/// let coordinator = DeepLinkCoordinator(
///     routing: routing,
///     handler: handler,
///     middlewareCoordinator: customMiddlewareCoordinator,
///     routeExecutionDelay: .milliseconds(250)
/// )
/// ```
///
/// ## Thread Safety
///
/// Thread-safe coordinator for handling deep links.
///
/// Thread safety is achieved through:
/// - Core stored properties (routing, handler, middlewareCoordinator) are immutable (`let`)
/// - The `delegate` property is `@MainActor`-isolated via protocol conformance
/// - All protocols conform to `Sendable`
///
/// - Parameter Route: The type of route that this coordinator handles
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: Sendable {
	private let log: LoggingProvider
	private let logPrivacy: DeepLinkLogPrivacy

	// MARK: - Private Properties

	private let routing: any DeepLinkRouting<Route>
	private let handler: any DeepLinkHandler<Route>
	private let middlewareCoordinator: DeepLinkMiddlewareCoordinator
	private let routeExecutionDelay: Duration
	private let broadcaster = ResultBroadcaster<Route>()

	// MARK: - Public Properties

	/// The delegate that receives notifications about deep link processing events.
	///
	/// The delegate is called on the main thread to ensure thread safety and proper UI updates.
	/// Set this to receive notifications about:
	/// - Deep link processing start (`willProcess`)
	/// - Deep link processing completion (`didProcess`)
	/// - Deep link processing failures (`didFailProcessing`)
	public let delegate: (any DeepLinkCoordinatorDelegate<Route>)?

	/// Injectable sleep primitive used between route executions when
	/// ``routeExecutionDelay`` is positive. Defaults to `Task.sleep(for:)`;
	/// tests can inject a no-op or a recorder closure to retire wall-clock
	/// waits.
	private let sleep: @Sendable (Duration) async -> Void

	/// A stream of every result this coordinator produces from now on.
	///
	/// Each access returns a new, independent stream; every live stream
	/// receives every result (successful, failed or stopped by middleware)
	/// from ``handle(url:)``, ``markReadyAndDrain(queue:)`` and
	/// ``resumePendingLinks(from:)``, in completion order. Results produced
	/// before the stream was created are not replayed. A stream buffers at
	/// most 100 undelivered results and drops the oldest beyond that. Streams
	/// finish when the coordinator is deallocated; cancelling the consuming
	/// task unsubscribes.
	///
	/// ```swift
	/// .task {
	///     for await result in coordinator.results where !result.wasSuccessful {
	///         errorBanner = result.firstDeepLinkError?.redactedDescription
	///     }
	/// }
	/// ```
	public var results: AsyncStream<DeepLinkResult<Route>> {
		broadcaster.makeStream()
	}

	// MARK: - Initialization

	/// Creates a new deep link coordinator with all necessary components.
	///
	/// This initializer creates a fully functional deep link coordinator that can process
	/// deep link URLs through the complete pipeline: middleware → routing → handling.
	/// For easier configuration with defaults, use `DeepLinkCoordinatorBuilder` instead.
	///
	/// - Parameters:
	///   - routing: The routing implementation responsible for converting processed URLs to routes.
	///     Typically `DefaultDeepLinkRouting` with an array of parsers.
	///   - handler: The handler implementation responsible for executing the appropriate actions
	///     for each route. Handles navigation, state updates, or other app-specific logic.
	///   - middlewareCoordinator: The middleware coordinator for processing URLs through middleware.
	///     Can be pre-configured with middleware, or empty for middleware-free operation.
	///     Defaults to a new empty coordinator.
	///   - routeExecutionDelay: The delay inserted between route handler executions.
	///     Useful when a stack of routes would otherwise trigger jarring, rapid
	///     navigation updates; pass any positive `Duration` to opt in. Default:
	///     `.zero` (no delay — the handler fires for each route back-to-back).
	///   - delegate: An optional delegate that receives notifications about deep link processing
	///     lifecycle events (willProcess, didProcess, didFailProcessing). Useful for analytics,
	///     logging, or other monitoring. Defaults to `nil`.
	///   - sleep: The sleep primitive used for `routeExecutionDelay`.
	///   - logPrivacy: How the coordinator's error logs describe URLs and errors.
	///     Defaults to ``DeepLinkLogPrivacy/redacted``.
	///
	/// ## Thread Safety
	///
	/// The coordinator is thread-safe and can be safely shared across threads and actors.
	/// The delegate methods are always called on the main thread for UI safety.
	///
	/// ## Delegate Notifications
	///
	/// When a delegate is provided, it receives notifications on the main thread about:
	/// - **willProcess**: Before processing begins
	/// - **didProcess**: After processing completes (success or failure)
	/// - **didFailProcessing**: When an error prevents processing from completing
	///
	/// ## Builder Alternative
	///
	/// For more convenient configuration with defaults, use `DeepLinkCoordinatorBuilder`:
	///
	/// ```swift
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .routing(routing)
	///     .handler(handler)
	///     .middleware(.security(), .logging())
	///     .build()
	/// ```
	public convenience init(
		routing: any DeepLinkRouting<Route>,
		handler: any DeepLinkHandler<Route>,
		middlewareCoordinator: DeepLinkMiddlewareCoordinator = DeepLinkMiddlewareCoordinator(),
		routeExecutionDelay: Duration = .zero,
		delegate: (any DeepLinkCoordinatorDelegate<Route>)? = nil,
		sleep: @Sendable @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
		logPrivacy: DeepLinkLogPrivacy = .redacted,
	) {
		self.init(
			routing: routing,
			handler: handler,
			middlewareCoordinator: middlewareCoordinator,
			routeExecutionDelay: routeExecutionDelay,
			delegate: delegate,
			sleep: sleep,
			logPrivacy: logPrivacy,
			log: .systemLogger(Logger(subsystem: "swift-deep-links", category: "DeepLinkCoordinator")),
		)
	}

	init(
		routing: any DeepLinkRouting<Route>,
		handler: any DeepLinkHandler<Route>,
		middlewareCoordinator: DeepLinkMiddlewareCoordinator = DeepLinkMiddlewareCoordinator(),
		routeExecutionDelay: Duration = .zero,
		delegate: (any DeepLinkCoordinatorDelegate<Route>)? = nil,
		sleep: @Sendable @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
		logPrivacy: DeepLinkLogPrivacy = .redacted,
		log: LoggingProvider,
	) {
		self.log = log
		self.logPrivacy = logPrivacy
		self.routing = routing
		self.handler = handler
		self.middlewareCoordinator = middlewareCoordinator
		self.routeExecutionDelay = routeExecutionDelay
		self.delegate = delegate
		self.sleep = sleep
	}

	// MARK: - Public Interface

	/// Handles a deep link URL by processing it through middleware, routing it, and executing the appropriate actions.
	///
	/// This method performs the complete deep link handling flow:
	/// 1. Notifies the delegate that processing will begin
	/// 2. Processes the URL through all registered middleware
	/// 3. Routes the processed URL to determine the appropriate routes
	/// 4. Executes each route through the handler with customizable delays
	/// 5. Notifies the delegate about the processing result
	/// 6. Returns comprehensive information about the processing result
	///
	/// The link runs with a ``DeepLinkContext/unknown`` context; prefer
	/// ``handle(url:context:)`` so middleware can apply per-source policy.
	///
	/// - Parameter url: The deep link URL to handle
	/// - Returns: A `DeepLinkResult` containing detailed information about the processing
	@discardableResult
	public func handle(url: URL) async -> DeepLinkResult<Route> {
		await handle(url: url, context: .unknown)
	}

	/// Handles a deep link URL that arrived through the channel described by `context`.
	///
	/// Middleware receives a ``DeepLinkRequest`` carrying `context`, and the
	/// handler receives the context middleware returned through
	/// ``DeepLinkHandler/handle(_:context:)``.
	///
	/// ```swift
	/// func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
	///     for item in contexts {
	///         let context = DeepLinkContext.openedURL(
	///             item.url,
	///             sourceApplication: item.options.sourceApplication,
	///             sceneID: scene.session.persistentIdentifier
	///         )
	///         Task { await coordinator.handle(url: item.url, context: context) }
	///     }
	/// }
	/// ```
	///
	/// - Parameters:
	///   - url: The deep link URL to handle
	///   - context: Where the link came from
	/// - Returns: A `DeepLinkResult` containing detailed information about the processing
	@discardableResult
	public func handle(url: URL, context: DeepLinkContext) async -> DeepLinkResult<Route> {
		await handle(DeepLinkRequest(url: url, context: context)) { [middlewareCoordinator] in
			try await middlewareCoordinator.process($0)
		}
	}
}

// MARK: - Readiness-Resuming Entry Point

extension DeepLinkCoordinator {
	/// Handles a URL drained from `queue` by resuming the middleware chain
	/// after the ``ReadinessMiddleware`` gating that queue, so middleware that
	/// already ran is not repeated while later middleware (authentication,
	/// security, rate limiting) still evaluates the link at drain time.
	@discardableResult
	func handleResumingAfterReadiness(url: URL, of queue: any ReadinessQueue) async -> DeepLinkResult<Route> {
		await handle(DeepLinkRequest(url: url)) { [middlewareCoordinator] in
			try await middlewareCoordinator.process($0, resumingAfterReadinessOf: queue)
		}
	}
}

// MARK: - Private Processing Methods

private extension DeepLinkCoordinator {
	func handle(
		_ request: DeepLinkRequest,
		middlewareStage: (DeepLinkRequest) async throws -> DeepLinkRequest?,
	) async -> DeepLinkResult<Route> {
		let url = request.url
		await notifyDelegateWillProcess(url)

		let startTime = Date()

		let result: DeepLinkResult<Route>
		do {
			result = try await processDeepLink(request, startTime: startTime, middlewareStage: middlewareStage)
		} catch {
			result = await handleProcessingError(url: url, error: error, startTime: startTime)
		}

		broadcaster.publish(result)
		return result
	}

	/// Processes the deep link through the complete pipeline.
	///
	/// - Parameters:
	///   - request: The request to process
	///   - startTime: The start time for execution timing
	///   - middlewareStage: The middleware processing applied before routing
	/// - Returns: The processing result
	func processDeepLink(
		_ request: DeepLinkRequest,
		startTime: Date,
		middlewareStage: (DeepLinkRequest) async throws -> DeepLinkRequest?,
	) async throws -> DeepLinkResult<Route> {
		guard let processed = try await middlewareStage(request) else {
			return await createMiddlewareStoppedResult(url: request.url, startTime: startTime)
		}

		let routes = try await routeURL(processed.url)
		let executionResult = await executeRoutes(routes, context: processed.context)

		return await createSuccessResult(
			originalURL: request.url,
			processedURL: processed.url,
			routes: routes,
			executionResult: executionResult,
			startTime: startTime,
		)
	}

	/// Routes the processed URL to determine the appropriate routes.
	///
	/// - Parameter url: The processed URL to route
	/// - Returns: An array of routes
	func routeURL(_ url: URL) async throws -> [Route] {
		try await routing.route(from: url)
	}

	/// Executes all routes with customizable delays.
	///
	/// - Parameters:
	///   - routes: The routes to execute
	///   - context: The context handed to the handler with each route
	/// - Returns: The execution result containing success/failure counts and errors
	func executeRoutes(_ routes: [Route], context: DeepLinkContext) async -> RouteExecutionResult {
		var successfulRoutes = 0
		var failedRoutes = 0
		var errors: [any Error] = []

		for (index, route) in routes.enumerated() {
			do {
				try await handler.handle(route, context: context)
				successfulRoutes += 1
			} catch {
				failedRoutes += 1
				errors.append(error)
				log.log(level: .error, "Error handling route \(route.id): \(logPrivacy.describe(error))")
			}

			if routeExecutionDelay > .zero, index < routes.count - 1 {
				await sleep(routeExecutionDelay)
			}
		}

		return RouteExecutionResult(
			successfulRoutes: successfulRoutes,
			failedRoutes: failedRoutes,
			errors: errors,
		)
	}

	/// Handles processing errors and creates an error result.
	///
	/// - Parameters:
	///   - url: The URL that failed to process
	///   - error: The error that occurred
	///   - startTime: The start time for execution timing
	/// - Returns: An error result
	func handleProcessingError(url: URL, error: Error, startTime: Date) async -> DeepLinkResult<Route> {
		log.log(level: .error, "Error while handling deep link \(url.host() ?? "Unknown URL host"): \(logPrivacy.describe(error))")

		await notifyDelegateDidFailProcessing(url, error: error)

		let executionTime = Date().timeIntervalSince(startTime)
		return DeepLinkResult<Route>(
			originalURL: url,
			processedURL: nil,
			routes: [],
			executionTime: executionTime,
			errors: [error],
			successfulRoutes: 0,
			failedRoutes: 0,
		)
	}

	/// Creates a result when middleware stops processing.
	///
	/// - Parameters:
	///   - url: The original URL
	///   - startTime: The start time for execution timing
	/// - Returns: A middleware-stopped result
	func createMiddlewareStoppedResult(url: URL, startTime: Date) async -> DeepLinkResult<Route> {
		log.log(level: .info, "Deep link processing stopped by middleware")

		let executionTime = Date().timeIntervalSince(startTime)
		let result = DeepLinkResult<Route>(
			originalURL: url,
			processedURL: nil,
			routes: [],
			executionTime: executionTime,
			errors: [],
			successfulRoutes: 0,
			failedRoutes: 0,
		)

		await notifyDelegateDidProcess(url, result: result)
		return result
	}

	/// Creates a successful processing result.
	///
	/// - Parameters:
	///   - originalURL: The original URL
	///   - processedURL: The processed URL
	///   - routes: The routes that were executed
	///   - executionResult: The execution result
	///   - startTime: The start time for execution timing
	/// - Returns: A successful result
	func createSuccessResult(
		originalURL: URL,
		processedURL: URL,
		routes: [Route],
		executionResult: RouteExecutionResult,
		startTime: Date,
	) async -> DeepLinkResult<Route> {
		let executionTime = Date().timeIntervalSince(startTime)
		let result = DeepLinkResult<Route>(
			originalURL: originalURL,
			processedURL: processedURL,
			routes: routes,
			executionTime: executionTime,
			errors: executionResult.errors,
			successfulRoutes: executionResult.successfulRoutes,
			failedRoutes: executionResult.failedRoutes,
		)

		await notifyDelegateDidProcess(originalURL, result: result)
		return result
	}
}

// MARK: - Helper Types

/// Represents the result of route execution.
private struct RouteExecutionResult {
	let successfulRoutes: Int
	let failedRoutes: Int
	let errors: [any Error]
}

// MARK: - Delegate Notifications

private extension DeepLinkCoordinator {
	/// Notifies the delegate that processing will begin.
	///
	/// - Parameter url: The URL that will be processed
	func notifyDelegateWillProcess(_ url: URL) async {
		guard let delegate else { return }

		await delegate.coordinator(self, willProcess: url)
	}

	/// Notifies the delegate that processing has completed.
	///
	/// - Parameters:
	///   - url: The URL that was processed
	///   - result: The result of the processing
	func notifyDelegateDidProcess(_ url: URL, result: DeepLinkResult<Route>) async {
		guard let delegate else { return }

		await delegate.coordinator(self, didProcess: url, result: result)
	}

	/// Notifies the delegate that processing has failed.
	///
	/// - Parameters:
	///   - url: The URL that failed to process
	///   - error: The error that caused the failure
	func notifyDelegateDidFailProcessing(_ url: URL, error: Error) async {
		guard let delegate else { return }

		await delegate.coordinator(self, didFailProcessing: url, error: error)
	}
}

// MARK: - Middleware Management

public extension DeepLinkCoordinator {
	/// Adds middleware to the coordinator.
	///
	/// Middleware is executed in the order it's added. The first middleware added
	/// will be the first to intercept URLs. This allows dynamic middleware configuration
	/// after the coordinator has been created.
	///
	/// ## Thread Safety
	///
	/// This method is thread-safe and can be called from any thread.
	///
	/// - Parameter middleware: The middleware to add
	func add(_ middleware: any DeepLinkMiddleware) async {
		await middlewareCoordinator.add(middleware)
	}

	/// Removes all middleware from the coordinator.
	///
	/// After calling this method, the coordinator will process URLs without any
	/// middleware interception. URLs will go directly to the routing system.
	///
	/// ## Thread Safety
	///
	/// This method is thread-safe and can be called from any thread.
	func removeAllMiddleware() async {
		await middlewareCoordinator.removeAll()
	}

	/// Removes all middleware of a specific type.
	///
	/// This method removes all instances of the specified middleware type from the
	/// coordinator's middleware stack. If no middleware of that type is found,
	/// this method completes without error.
	///
	/// ## Thread Safety
	///
	/// This method is thread-safe and can be called from any thread.
	///
	/// - Parameter type: The type of middleware to remove
	func removeMiddleware(_ type: (some DeepLinkMiddleware).Type) async {
		await middlewareCoordinator.remove(type)
	}
}
