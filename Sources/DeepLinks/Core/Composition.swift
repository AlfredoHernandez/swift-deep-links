//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

// MARK: - Functional Composition

/// Composes multiple delegates into a single composite delegate.
///
/// This function provides a clean, functional way to combine multiple delegates
/// without using operators, following modern Point-Free conventions.
///
/// ## Usage
///
/// ```swift
/// let delegate = compose(delegateA, delegateB, delegateC)
/// ```
///
/// ## Variadic Parameters
///
/// The function accepts any number of delegates and combines them into a
/// composite that executes all delegates in order.
///
/// ## Thread Safety
///
/// The resulting composite delegate is thread-safe and can be used concurrently.
///
/// - Parameter delegates: The delegates to compose, in execution order
/// - Returns: A composite delegate that executes all provided delegates
@MainActor
public func compose(
	_ delegates: DeepLinkCoordinatorDelegate...,
) -> CompositeDeepLinkDelegate {
	CompositeDeepLinkDelegate(delegates: delegates)
}

/// Composes multiple delegates from an array into a single composite delegate.
///
/// This overload accepts an array of delegates, useful when building delegate
/// lists dynamically or from configuration.
///
/// ## Usage
///
/// ```swift
/// let delegateList: [DeepLinkCoordinatorDelegate] = [delegateA, delegateB]
/// let delegate = compose(delegateList)
/// ```
///
/// - Parameter delegates: Array of delegates to compose
/// - Returns: A composite delegate that executes all provided delegates
@MainActor
public func compose(
	_ delegates: [DeepLinkCoordinatorDelegate],
) -> CompositeDeepLinkDelegate {
	CompositeDeepLinkDelegate(delegates: delegates)
}

/// Composes multiple middleware into an array for convenient configuration.
///
/// This function provides a clean way to group middleware together,
/// making configuration more readable and maintainable.
///
/// ## Usage
///
/// ```swift
/// let middleware = compose(middlewareA, middlewareB, middlewareC)
/// builder.addingMiddleware(middleware)
/// ```
///
/// - Parameter middleware: The middleware to compose, in execution order
/// - Returns: An array of middleware in the specified order
public func compose(
	_ middleware: any DeepLinkMiddleware...,
) -> [any DeepLinkMiddleware] {
	middleware
}

/// Composes multiple middleware from an array.
///
/// This overload accepts an array of middleware, useful when building middleware
/// lists dynamically or from configuration.
///
/// ## Usage
///
/// ```swift
/// let middlewareList: [any DeepLinkMiddleware] = [middlewareA, middlewareB]
/// let middleware = compose(middlewareList)
/// ```
///
/// - Parameter middleware: Array of middleware to compose
/// - Returns: The same array of middleware
public func compose(
	_ middleware: [any DeepLinkMiddleware],
) -> [any DeepLinkMiddleware] {
	middleware
}
