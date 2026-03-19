//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// Alert presentation routes for system notifications and user feedback.
///
/// This enum defines all routes that are presented as system alerts,
/// providing type-safe navigation for alert-based user interactions.
///
/// ## Supported Alert Types:
/// - **Info**: Informational messages with neutral styling
/// - **Warning**: Warning messages with caution styling
/// - **Error**: Error messages with error styling
/// - **Success**: Success messages with positive styling
///
/// ## Conformance:
/// - `Identifiable`: Required for SwiftUI alert presentation
/// - `DeepLinkRoute`: Enables deep link parsing and routing
///
/// ## Usage:
/// These routes are used when deep links should trigger system alert presentations
/// to provide immediate feedback or notifications to users.
enum Alert: Identifiable, DeepLinkRoute {
	/// Present a system alert with specified content and type
	/// - Parameters:
	///   - title: The alert title
	///   - message: The alert message content
	///   - type: The alert type for styling and categorization
	case alert(title: String, message: String, type: AlertType)

	/// Alert type enumeration for different alert styles and purposes.
	///
	/// Each type provides semantic meaning and can be used for:
	/// - Visual styling and icon selection
	/// - User experience categorization
	/// - Analytics and logging purposes
	enum AlertType: String, CaseIterable {
		/// Informational alert with neutral styling
		case info
		/// Warning alert with caution styling
		case warning
		/// Error alert with error styling
		case error
		/// Success alert with positive styling
		case success
	}

	/// Provides a unique identifier for each alert route.
	///
	/// The identifier is constructed from the alert parameters to ensure
	/// uniqueness and enable proper alert state management.
	///
	/// - Returns: A unique string identifier for the route
	var id: String {
		switch self {
		case let .alert(title, message, type):
			"alert_\(type.rawValue)_\(title)_\(message)"
		}
	}
}
