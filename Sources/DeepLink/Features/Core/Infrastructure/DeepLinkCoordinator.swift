//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// coordinator.add(AnalyticsMiddleware())
/// coordinator.add(AuthenticationMiddleware())
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
/// This class uses `@unchecked Sendable` because:
/// - Core stored properties (routing, handler, middlewareCoordinator) are immutable (`let`)
/// - The `delegate` property is mutable (`var`) but all delegate calls are dispatched to MainActor for UI safety
/// - No other mutable state is shared across threads
///
/// The `@unchecked` annotation is used because protocol types (`DeepLinkRouting`,
/// `DeepLinkHandler`, `DeepLinkCoordinatorDelegate`) don't conform to `Sendable`,
/// allowing implementers flexibility in their concurrency approaches while maintaining
/// thread safety through MainActor isolation for delegate calls.
///
/// - Parameter Route: The type of route that this coordinator handles
public final class DeepLinkCoordinator<Route: DeepLinkRoute>: @unchecked Sendable {
    private let logger = Logger(subsystem: "swift-deep-link", category: "DeepLinkCoordinator")

    // MARK: - Private Properties

    private let routing: any DeepLinkRouting<Route>
    private let handler: any DeepLinkHandler<Route>
    private let middlewareCoordinator: DeepLinkMiddlewareCoordinator
    private let routeExecutionDelay: Duration

    // MARK: - Public Properties

    /// The delegate that receives notifications about deep link processing events.
    ///
    /// The delegate is called on the main thread to ensure thread safety and proper UI updates.
    /// Set this to receive notifications about:
    /// - Deep link processing start (`willProcess`)
    /// - Deep link processing completion (`didProcess`)
    /// - Deep link processing failures (`didFailProcessing`)
    public var delegate: (any DeepLinkCoordinatorDelegate)?

    // MARK: - Initialization

    /// Creates a new deep link coordinator.
    ///
    /// - Parameters:
    ///   - routing: The routing implementation responsible for converting URLs to routes
    ///   - handler: The handler implementation responsible for executing route actions
    ///   - middlewareCoordinator: The middleware coordinator for processing URLs through middleware
    ///   - routeExecutionDelay: The delay between route executions for better UX (default: 500ms)
    ///   - delegate: The delegate that receives notifications about deep link processing events (optional)
    ///
    /// ## Delegate Notifications
    ///
    /// The delegate (if provided) is called on the main thread to ensure thread safety and proper UI updates.
    /// It receives notifications about:
    /// - Deep link processing start (`willProcess`)
    /// - Deep link processing completion (`didProcess`)
    /// - Deep link processing failures (`didFailProcessing`)
    public init(
        routing: any DeepLinkRouting<Route>,
        handler: any DeepLinkHandler<Route>,
        middlewareCoordinator: DeepLinkMiddlewareCoordinator = DeepLinkMiddlewareCoordinator(),
        routeExecutionDelay: Duration = .milliseconds(500),
        delegate: (any DeepLinkCoordinatorDelegate)? = nil,
    ) {
        self.routing = routing
        self.handler = handler
        self.middlewareCoordinator = middlewareCoordinator
        self.routeExecutionDelay = routeExecutionDelay
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
    /// - Parameter url: The deep link URL to handle
    /// - Returns: A `DeepLinkResult` containing detailed information about the processing
    @discardableResult
    public func handle(url: URL) async -> DeepLinkResult<Route> {
        await notifyDelegateWillProcess(url)

        let startTime = Date()

        do {
            return try await processDeepLink(url: url, startTime: startTime)
        } catch {
            return await handleProcessingError(url: url, error: error, startTime: startTime)
        }
    }
}

// MARK: - Private Processing Methods

private extension DeepLinkCoordinator {
    /// Processes the deep link through the complete pipeline.
    ///
    /// - Parameters:
    ///   - url: The URL to process
    ///   - startTime: The start time for execution timing
    /// - Returns: The processing result
    func processDeepLink(url: URL, startTime: Date) async throws -> DeepLinkResult<Route> {
        let processedURL = try await processThroughMiddleware(url)

        guard let processedURL else {
            return await createMiddlewareStoppedResult(url: url, startTime: startTime)
        }

        let routes = try await routeURL(processedURL)
        let executionResult = await executeRoutes(routes)

        return await createSuccessResult(
            originalURL: url,
            processedURL: processedURL,
            routes: routes,
            executionResult: executionResult,
            startTime: startTime,
        )
    }

    /// Processes the URL through middleware.
    ///
    /// - Parameter url: The URL to process
    /// - Returns: The processed URL or nil if stopped by middleware
    func processThroughMiddleware(_ url: URL) async throws -> URL? {
        try await middlewareCoordinator.process(url)
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
    /// - Parameter routes: The routes to execute
    /// - Returns: The execution result containing success/failure counts and errors
    func executeRoutes(_ routes: [Route]) async -> RouteExecutionResult {
        var successfulRoutes = 0
        var failedRoutes = 0
        var errors: [Error] = []

        for route in routes {
            do {
                try await handler.handle(route)
                successfulRoutes += 1

                // Add delay between route executions for better UX
                try? await Task.sleep(for: routeExecutionDelay)
            } catch {
                failedRoutes += 1
                errors.append(error)
                logger.error("Error handling route \(route.id): \(error)")
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
        logger.error("Error while handling deep link \(String(url.host() ?? "Unknown URL host")): \(error)")

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
        logger.info("Deep link processing stopped by middleware")

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
    let errors: [Error]
}

// MARK: - Delegate Notifications

private extension DeepLinkCoordinator {
    /// Notifies the delegate that processing will begin.
    ///
    /// - Parameter url: The URL that will be processed
    func notifyDelegateWillProcess(_ url: URL) async {
        guard let delegate else { return }

        await MainActor.run {
            delegate.coordinator(self, willProcess: url)
        }
    }

    /// Notifies the delegate that processing has completed.
    ///
    /// - Parameters:
    ///   - url: The URL that was processed
    ///   - result: The result of the processing
    func notifyDelegateDidProcess(_ url: URL, result: DeepLinkResult<Route>) async {
        guard let delegate else { return }

        await MainActor.run {
            delegate.coordinator(self, didProcess: url, result: result)
        }
    }

    /// Notifies the delegate that processing has failed.
    ///
    /// - Parameters:
    ///   - url: The URL that failed to process
    ///   - error: The error that caused the failure
    func notifyDelegateDidFailProcessing(_ url: URL, error: Error) async {
        guard let delegate else { return }

        await MainActor.run {
            delegate.coordinator(self, didFailProcessing: url, error: error)
        }
    }
}

// MARK: - Middleware Management

public extension DeepLinkCoordinator {
    /// Adds middleware to the coordinator.
    ///
    /// Middleware is executed in the order it's added. The first middleware added
    /// will be the first to intercept URLs.
    ///
    /// - Parameter middleware: The middleware to add
    func add(_ middleware: any DeepLinkMiddleware) async {
        await middlewareCoordinator.add(middleware)
    }

    /// Adds advanced middleware to the coordinator.
    ///
    /// - Parameter middleware: The advanced middleware to add
    func add(_ middleware: any AdvancedDeepLinkMiddleware) async {
        await middlewareCoordinator.add(middleware)
    }

    /// Removes all middleware from the coordinator.
    func removeAllMiddleware() async {
        await middlewareCoordinator.removeAll()
    }

    /// Removes middleware of a specific type.
    ///
    /// - Parameter type: The type of middleware to remove
    func removeMiddleware(_ type: (some DeepLinkMiddleware).Type) async {
        await middlewareCoordinator.remove(type)
    }
}
