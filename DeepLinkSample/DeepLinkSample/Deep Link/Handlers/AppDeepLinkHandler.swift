//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks

/// A deep link handler that processes `AppRoute` instances and triggers navigation actions.
///
/// This handler serves as the bridge between the deep link parsing system and the
/// app's navigation infrastructure. It receives parsed routes and translates them
/// into appropriate navigation actions using the `NavigationRouter`.
///
/// ## Supported Route Types:
/// - **Stack routes**: Triggers navigation stack pushes
/// - **Sheet routes**: Triggers modal sheet presentations
/// - **Alert routes**: Triggers system alert presentations
///
/// ## Architecture:
/// The handler uses pattern matching to determine the appropriate navigation action
/// for each route type and updates the navigation state accordingly.
///
/// ## Usage:
/// This handler is typically used with the `DeepLinkCoordinator` to process
/// parsed deep link routes and execute the corresponding navigation actions.
///
/// ## Type Aliases:
/// This handler demonstrates the use of the `HandlerOf<Route>` type alias
/// for cleaner type signatures when conforming to `DeepLinkHandler`.
final class AppDeepLinkHandler: DeepLinkHandler {
	typealias Route = AppRoute
	private let navigationRouter: NavigationRouter

	/// Initializes the handler with a navigation router.
	///
	/// - Parameter navigationRouter: The router used to manage navigation state
	init(navigationRouter: NavigationRouter) {
		self.navigationRouter = navigationRouter
	}

	/// Handles a parsed deep link route by executing the appropriate navigation action.
	///
	/// This method processes different route types and triggers the corresponding
	/// navigation behavior:
	/// - Stack routes: Pushes to the navigation stack
	/// - Sheet routes: Presents modal sheets
	/// - Alert routes: Shows system alerts
	///
	/// - Parameter route: The parsed deep link route to handle
	/// - Throws: No errors are currently thrown, but the method signature supports future error handling
	func handle(_ route: AppRoute) async throws {
		await MainActor.run {
			switch route {
			case let .stack(navigationRoute):
				navigationRouter.push(to: navigationRoute)

			case let .sheet(sheet):
				navigationRouter.sheet = sheet

			case let .alert(alert):
				switch alert {
				case let .alert(title, message, type):
					navigationRouter.alert = NavigationRouter.AlertItem(
						title: title,
						message: message,
						type: Alert.AlertType(rawValue: type.rawValue) ?? .info,
					)
				}
			}
		}
	}
}
