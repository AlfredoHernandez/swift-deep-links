//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink

/// Navigation stack routes for push-based navigation.
///
/// This enum defines all routes that are handled through the `NavigationStack`
/// system, providing type-safe navigation for stack-based views.
///
/// ## Supported Routes:
/// - **Product routes**: Navigate to product detail views with product ID and category
/// - **Settings routes**: Navigate to specific settings sections
///
/// ## Conformance:
/// - `DeepLinkRoute`: Enables deep link parsing and routing
/// - `Hashable`: Required for `NavigationStack` path management
///
/// ## Usage:
/// These routes are used when deep links should trigger navigation stack pushes
/// rather than modal presentations. They integrate with SwiftUI's `NavigationStack`
/// and `navigationDestination` modifiers.
enum Stack: DeepLinkRoute, Hashable {
    /// Navigate to a product detail view
    /// - Parameters:
    ///   - productID: The unique identifier of the product
    ///   - category: Optional category for additional context
    case product(productID: String, category: String?)

    /// Navigate to a specific settings section
    /// - Parameter section: The settings section to display
    case settings(section: String)

    /// Provides a unique identifier for each stack route.
    ///
    /// The identifier is constructed from the route parameters to ensure
    /// uniqueness and enable proper navigation state management.
    ///
    /// - Returns: A unique string identifier for the route
    var id: String {
        switch self {
        case let .product(productID, category):
            "product_\(productID)_\(category ?? "")"

        case let .settings(section):
            "settings_\(section)"
        }
    }
}
