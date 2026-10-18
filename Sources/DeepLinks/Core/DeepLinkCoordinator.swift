//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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
/// ## Cancellation
///
/// Cancelling the task that awaits ``handle(url:context:)`` does not abandon
/// the link: every route still reaches the handler, middleware is still told
/// how the link ended through ``DeepLinkMiddleware/didFinish(_:outcome:)``,
/// and the result is still delivered and published to ``results``. A link
/// that already passed security checks is never left half-settled. The default
/// sleep returns at once in a cancelled task, so `routeExecutionDelay` is
/// skipped; handlers that should stop early can check `Task.isCancelled`.
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
	private let routeExecutor: RouteExecutor<Route>
	let middlewareCoordinator: DeepLinkMiddlewareCoordinator
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
		routeExecutor = RouteExecutor(handler: handler, delay: routeExecutionDelay, sleep: sleep, log: log, logPrivacy: logPrivacy)
		self.middlewareCoordinator = middlewareCoordinator
		self.delegate = delegate
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
			await middlewareCoordinator.trackedProcess($0)
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
	func handleResumingAfterReadiness(_ request: DeepLinkRequest, of queue: any ReadinessQueue) async -> DeepLinkResult<Route> {
		await handle(request) { [middlewareCoordinator] in
			await middlewareCoordinator.trackedProcess($0, resumingAfterReadinessOf: queue)
		}
	}
}

// MARK: - Private Processing Methods

private extension DeepLinkCoordinator {
	func handle(
		_ request: DeepLinkRequest,
		middlewareStage: (DeepLinkRequest) async -> MiddlewareRun,
	) async -> DeepLinkResult<Route> {
		await DeepLinkRun.updating({
			$0.id = UUID()
			$0.arrival = request.deferral?.arrival ?? request
		}) {
			await handleInRun(request, middlewareStage: middlewareStage)
		}
	}

	func handleInRun(
		_ request: DeepLinkRequest,
		middlewareStage: (DeepLinkRequest) async -> MiddlewareRun,
	) async -> DeepLinkResult<Route> {
		await notifyDelegateWillProcess(request.url)

		let startTime = Date()
		let run = await middlewareStage(request)
		let (result, outcome) = await process(request, after: run, startTime: startTime)
		await run.finish(with: outcome)
		if !run.wasDeferred {
			await request.deferral?.settle(with: outcome)
		}

		broadcaster.publish(result)
		return result
	}

	/// Routes and handles the request the middleware chain produced, and
	/// reports how processing ended for ``DeepLinkMiddleware/didFinish(_:outcome:)``.
	func process(
		_ request: DeepLinkRequest,
		after run: MiddlewareRun,
		startTime: Date,
	) async -> (DeepLinkResult<Route>, DeepLinkOutcome) {
		let processed: DeepLinkRequest
		switch run.result {
		case let .failure(error):
			return await (fail(url: request.url, error: error, startTime: startTime), .failed(error))

		case .success(nil):
			log.log(level: .info, "Deep link processing stopped by middleware")
			let result = DeepLinkResultFactory<Route>.stopped(url: request.url, startTime: startTime)
			await notifyDelegateDidProcess(request.url, result: result)
			return (result, run.wasDeferred ? .deferred : .stopped)

		case let .success(request?):
			processed = request.bindingSignatureToURL()
		}

		do {
			let routes = try await routing.route(from: processed.url)
			let execution = await DeepLinkRun.updating({ $0.routedURL = processed.url }) {
				await routeExecutor.execute(routes, context: processed.context)
			}
			let result = DeepLinkResultFactory.completed(
				originalURL: request.url,
				processedURL: processed.url,
				routes: routes,
				execution: execution,
				startTime: startTime,
			)
			await notifyDelegateDidProcess(request.url, result: result)
			return (result, execution.outcome)
		} catch {
			return await (fail(url: request.url, error: error, startTime: startTime), .failed(error))
		}
	}

	func fail(url: URL, error: any Error, startTime: Date) async -> DeepLinkResult<Route> {
		log.log(level: .error, "Error while handling deep link \(url.host() ?? "Unknown URL host"): \(logPrivacy.describe(error))")
		await notifyDelegateDidFailProcessing(url, error: error)
		return DeepLinkResultFactory.failed(url: url, error: error, startTime: startTime)
	}
}
