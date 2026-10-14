//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

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
public func compose<Route: DeepLinkRoute>(
	_ delegates: any DeepLinkCoordinatorDelegate<Route>...,
) -> CompositeDeepLinkDelegate<Route> {
	CompositeDeepLinkDelegate<Route>(delegates: delegates)
}

/// Composes multiple delegates from an array into a single composite delegate.
///
/// This overload accepts an array of delegates, useful when building delegate
/// lists dynamically or from configuration.
///
/// ## Usage
///
/// ```swift
/// let delegateList: [any DeepLinkCoordinatorDelegate<AppRoute>] = [delegateA, delegateB]
/// let delegate = compose(delegateList)
/// ```
///
/// - Parameter delegates: Array of delegates to compose
/// - Returns: A composite delegate that executes all provided delegates
@MainActor
public func compose<Route: DeepLinkRoute>(
	_ delegates: [any DeepLinkCoordinatorDelegate<Route>],
) -> CompositeDeepLinkDelegate<Route> {
	CompositeDeepLinkDelegate<Route>(delegates: delegates)
}
