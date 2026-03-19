//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// A unified route type that combines all application navigation routes.
///
/// This enum serves as the central routing system for the deep link infrastructure,
/// providing a single point of entry for all navigation patterns supported by the app.
///
/// ## Supported Navigation Types:
/// - **Sheet routes**: Modal presentations (Information, Profile)
/// - **Stack routes**: Navigation stack pushes (Product, Settings)
/// - **Alert routes**: System alert presentations (Info, Warning, Error, Success)
///
/// ## Deep Link Integration:
/// The `AppRoute` conforms to `DeepLinkRoute` protocol, making it compatible with
/// the deep link parsing and routing system. Each route type is handled by
/// specialized parsers and routed to appropriate navigation mechanisms.
///
/// ## Usage:
/// This enum is used throughout the app to:
/// - Define all possible navigation destinations
/// - Provide type-safe routing between different navigation patterns
/// - Enable deep link parsing and handling
/// - Maintain consistent navigation state management
enum AppRoute: DeepLinkRoute {
	/// Modal sheet presentation routes
	case sheet(Sheet)
	/// Navigation stack push routes
	case stack(Stack)
	/// Alert presentation routes
	case alert(Alert)

	/// Provides a unique identifier for each route type.
	///
	/// The identifier is used for:
	/// - Deep link route identification
	/// - Navigation state management
	/// - Debugging and logging purposes
	///
	/// - Returns: A unique string identifier prefixed with the route type
	var id: String {
		switch self {
		case let .sheet(sheet):
			"sheet_\(sheet.id)"

		case let .stack(navigationRoute):
			"stack_\(navigationRoute.id)"

		case let .alert(alert):
			"alert_\(alert.id)"
		}
	}
}
