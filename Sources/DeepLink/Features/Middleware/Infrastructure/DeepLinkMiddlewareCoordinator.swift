//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Coordinates the execution of middleware in sequence.
///
/// The middleware coordinator executes middleware in the order they were added,
/// allowing each middleware to intercept, transform, or stop the processing of
/// deep link URLs before they reach the parsers.
///
/// ## Usage Example
///
/// ```swift
/// let coordinator = DeepLinkMiddlewareCoordinator()
/// coordinator.add(AnalyticsMiddleware())
/// coordinator.add(AuthenticationMiddleware())
/// coordinator.add(RateLimitMiddleware())
///
/// let processedURL = try await coordinator.process(url)
/// ```
public final class DeepLinkMiddlewareCoordinator: @unchecked Sendable {
    private var middleware: [any DeepLinkMiddleware] = []
    private let queue: DispatchQueue

    /// Creates a new middleware coordinator.
    ///
    /// - Parameter queue: DispatchQueue for thread-safe operations (defaults to a new concurrent queue
    ///   with label "io.alfredodhz.deeplink.middleware-coordinator")
    ///
    /// ## Examples
    ///
    /// ```swift
    /// // Use default queue
    /// let coordinator = DeepLinkMiddlewareCoordinator()
    ///
    /// // Use custom queue
    /// let customQueue = DispatchQueue(label: "com.myapp.middleware", attributes: .concurrent)
    /// let coordinator = DeepLinkMiddlewareCoordinator(queue: customQueue)
    /// ```
    public init(queue: DispatchQueue = DispatchQueue(label: "io.alfredodhz.deeplink.middleware-coordinator", attributes: .concurrent)) {
        self.queue = queue
    }

    /// Adds middleware to the coordinator.
    ///
    /// Middleware is executed in the order it's added. The first middleware added
    /// will be the first to intercept URLs.
    ///
    /// - Parameter middleware: The middleware to add
    public func add(_ middleware: any DeepLinkMiddleware) {
        queue.async(flags: .barrier) {
            self.middleware.append(middleware)
        }
    }

    /// Removes all middleware from the coordinator.
    public func removeAll() {
        queue.async(flags: .barrier) {
            self.middleware.removeAll()
        }
    }

    /// Removes middleware of a specific type.
    ///
    /// - Parameter type: The type of middleware to remove
    public func remove<T: DeepLinkMiddleware>(_: T.Type) {
        queue.async(flags: .barrier) {
            self.middleware.removeAll { $0 is T }
        }
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
        let currentMiddleware = await getCurrentMiddleware()
        var currentURL = url

        for middleware in currentMiddleware {
            let result = try await middleware.intercept(currentURL)

            // If middleware returns nil, stop processing
            guard let url = result else {
                return nil
            }

            currentURL = url
        }

        return currentURL
    }

    /// Gets the current list of middleware in a thread-safe manner.
    private func getCurrentMiddleware() async -> [any DeepLinkMiddleware] {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.middleware)
            }
        }
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
