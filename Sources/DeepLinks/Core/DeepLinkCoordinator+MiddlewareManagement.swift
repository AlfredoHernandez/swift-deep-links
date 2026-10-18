//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

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
