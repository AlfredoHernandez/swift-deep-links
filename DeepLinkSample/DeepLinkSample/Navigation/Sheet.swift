//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// Modal sheet presentation routes for overlay views.
///
/// This enum defines all routes that are presented as modal sheets,
/// providing type-safe navigation for overlay-based views.
///
/// ## Supported Routes:
/// - **Info routes**: Display information content in a modal sheet
/// - **Profile routes**: Show user profile information in a modal sheet
///
/// ## Conformance:
/// - `Identifiable`: Required for SwiftUI sheet presentation
/// - `DeepLinkRoute`: Enables deep link parsing and routing
///
/// ## Usage:
/// These routes are used when deep links should trigger modal sheet presentations
/// rather than navigation stack pushes. They integrate with SwiftUI's `.sheet`
/// modifier and provide a clean overlay experience.
enum Sheet: Identifiable, DeepLinkRoute {
	/// Present an information modal sheet
	/// - Parameters:
	///   - title: The title of the information content
	///   - brief: A brief description or summary
	case info(title: String, brief: String)

	/// Present a user profile modal sheet
	/// - Parameters:
	///   - userID: The unique identifier of the user
	///   - name: Optional display name of the user
	case profile(userID: String, name: String?)

	/// Provides a unique identifier for each sheet route.
	///
	/// The identifier is constructed from the route parameters to ensure
	/// uniqueness and enable proper sheet state management.
	///
	/// - Returns: A unique string identifier for the route
	var id: String {
		switch self {
		case let .info(title, brief):
			"info_\(title)_\(brief)"

		case let .profile(userID, name):
			"profile_\(userID)_\(name ?? "")"
		}
	}
}
