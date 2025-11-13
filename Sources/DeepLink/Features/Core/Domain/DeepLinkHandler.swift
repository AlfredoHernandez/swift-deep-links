//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
/// ## See Also
///
/// - ``HandlerOf``
///
/// - AssociatedType Route: The type of route this handler can process
public protocol DeepLinkHandler<Route> {
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
}
