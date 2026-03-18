//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Combine
import SwiftUI

/// A centralized navigation router that manages all navigation state in the app.
///
/// This class serves as the single source of truth for navigation state,
/// handling three types of navigation patterns:
/// - **Sheet presentations**: Modal overlays
/// - **Stack navigation**: Navigation stack pushes
/// - **Alert presentations**: System alerts
///
/// ## Architecture:
/// The router uses `@Published` properties to enable reactive UI updates
/// when navigation state changes. It integrates with SwiftUI's navigation
/// system and provides a clean API for programmatic navigation.
///
/// ## Usage:
/// The router is typically injected as an `@EnvironmentObject` and used
/// throughout the app to trigger navigation actions and manage state.
final class NavigationRouter: ObservableObject {
	/// Currently presented sheet, if any
	@Published var sheet: Sheet?

	/// Navigation stack path for stack-based navigation
	@Published var stack: [Stack] = []

	/// Currently presented alert, if any
	@Published var alert: AlertItem?

	/// Represents an alert item with all necessary information for presentation.
	///
	/// This struct encapsulates alert data and conforms to `Identifiable`
	/// for SwiftUI alert presentation.
	struct AlertItem: Identifiable {
		/// Unique identifier for the alert
		let id = UUID()
		/// Alert title
		let title: String
		/// Alert message content
		let message: String
		/// Alert type for styling and categorization
		let type: Alert.AlertType
	}

	/// Pushes a new route onto the navigation stack.
	///
	/// This method adds a new `Stack` route to the navigation path,
	/// triggering a navigation push in the `NavigationStack`.
	///
	/// - Parameter route: The stack route to push
	func push(to route: Stack) {
		stack.append(route)
	}
}
