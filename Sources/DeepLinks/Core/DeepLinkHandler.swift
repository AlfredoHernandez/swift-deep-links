//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

/// A protocol that defines how to handle specific deep link routes.
///
/// The `DeepLinkHandler` protocol is responsible for executing the actual actions
/// associated with each deep link route. It acts as the bridge between the routing
/// system and your application's navigation or business logic.
///
/// ## Implementation
///
/// Implement this protocol to define what happens when a specific route is triggered:
///
/// ```swift
/// final class AppDeepLinkHandler: DeepLinkHandler {
///     typealias Route = AppRoute
///
///     func handle(_ route: AppRoute) async throws {
///         switch route {
///         case .profile(let userId):
///             await navigateToProfile(userId: userID)
///         case .product(let productId):
///             await navigateToProduct(productId: productID)
///         }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// The `handle` method is async and should be implemented to handle any necessary
/// thread management, particularly when updating UI components.
///
/// - AssociatedType Route: The type of route this handler can process
public protocol DeepLinkHandler<Route>: Sendable {
	/// The type of route this handler can process.
	associatedtype Route: DeepLinkRoute

	/// Handles a specific deep link route by executing the appropriate action.
	///
	/// This method should contain the business logic for what happens when a
	/// particular route is triggered. It may involve navigation, data loading,
	/// or any other application-specific actions.
	///
	/// - Parameter route: The route to handle
	/// - Throws: Any error that occurs during route handling
	func handle(_ route: Route) async throws

	/// Handles a route together with the ``DeepLinkContext`` its link arrived with.
	///
	/// The coordinator calls this method. Implement it instead of
	/// ``handle(_:)`` when the handler needs the source or scene; implement
	/// exactly one of the two, because each defaults to the other (a type
	/// implementing neither throws ``DeepLinkError/missingRequiredConfiguration(_:)``).
	///
	/// - Parameters:
	///   - route: The route to handle
	///   - context: Where the link came from, after middleware ran
	/// - Throws: Any error that occurs during route handling
	func handle(_ route: Route, context: DeepLinkContext) async throws
}

public extension DeepLinkHandler {
	/// Ignores the context and calls ``handle(_:)``.
	func handle(_ route: Route, context _: DeepLinkContext) async throws {
		try await ProtocolBridgeGuard.bridge(Self.self, .handle, hop: .contextToLegacy) {
			try await handle(route)
		}
	}

	/// Calls ``handle(_:context:)`` with a ``DeepLinkContext/unknown`` context.
	func handle(_ route: Route) async throws {
		try await ProtocolBridgeGuard.bridge(Self.self, .handle, hop: .legacyToContext) {
			try await handle(route, context: .unknown)
		}
	}
}
