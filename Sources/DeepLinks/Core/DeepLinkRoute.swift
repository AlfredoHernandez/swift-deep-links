//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// A protocol that defines a deep link route within the application.
///
/// The `DeepLinkRoute` protocol represents a specific navigation destination or
/// action that can be triggered by a deep link. Each route should have a unique
/// identifier that can be used for routing, logging, and debugging purposes.
///
/// ## Implementation
///
/// Implement this protocol to define your application's specific routes:
///
/// ```swift
/// enum AppRoute: Identifiable, DeepLinkRoute {
///     case profile(userId: String)
///     case product(productId: String)
///     case settings(section: String)
///
///     var id: String {
///         switch self {
///         case .profile(let userId): "profile_\(userId)"
///         case .product(let productId): "product_\(productId)"
///         case .settings(let section): "settings_\(section)"
///         }
///     }
/// }
/// ```
///
/// ## Requirements
///
/// - `id`: A unique string identifier for the route
///
/// ## Best Practices
///
/// - Use descriptive identifiers that include relevant parameters
/// - Ensure identifiers are unique across all possible route combinations
/// - Consider including parameter values in the identifier for better debugging
public protocol DeepLinkRoute: Sendable {
	/// A unique identifier for this route.
	///
	/// This identifier should be unique across all possible route combinations
	/// and should include relevant parameters to aid in debugging and logging.
	var id: String { get }
}
