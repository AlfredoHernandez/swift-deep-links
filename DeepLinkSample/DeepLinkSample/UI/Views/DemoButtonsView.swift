//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// A view that displays demonstration buttons for different deep link types.
///
/// This view showcases all the different navigation patterns supported by the app:
/// - **Sheet presentations**: Information and Profile views
/// - **Navigation stack pushes**: Product and Settings views
/// - **Alert presentations**: Warning and error alerts
///
/// Each button demonstrates a specific deep link functionality and provides
/// immediate visual feedback when tapped. The buttons use different colors
/// to categorize the type of navigation they trigger.
///
/// The view integrates with the `NavigationRouter` to handle navigation state
/// and provides a comprehensive testing interface for deep link behaviors.
struct DemoButtonsView: View {
	@EnvironmentObject var navigationRouter: NavigationRouter

	var body: some View {
		VStack(spacing: 16) {
			Text("Demonstrations")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)

			// Deep link: deeplink://info - triggers modal sheet
			DemoButton(
				title: "Information",
				subtitle: "Show information sheet",
				icon: "info.circle",
				color: .blue,
			) {
				navigationRouter.sheet = .info(
					title: "Demo Information",
					brief: "This is a demonstration of the information deep link",
				)
			}

			// Deep link: deeplink://profile - triggers modal sheet
			DemoButton(
				title: "User Profile",
				subtitle: "View user profile",
				icon: "person.circle",
				color: .green,
			) {
				navigationRouter.sheet = .profile(
					userID: "demo-user-123",
					name: "Demo User",
				)
			}

			// Deep link: deeplink://product - triggers navigation stack push
			DemoButton(
				title: "Product",
				subtitle: "View product details",
				icon: "bag.circle",
				color: .orange,
			) {
				navigationRouter.push(to: .product(
					productID: "PROD-001",
					category: "Electronics",
				))
			}

			// Deep link: deeplink://settings - triggers navigation stack push
			DemoButton(
				title: "Settings",
				subtitle: "Open settings",
				icon: "gearshape.circle",
				color: .gray,
			) {
				navigationRouter.push(to: .settings(section: "account"))
			}

			// Deep link: deeplink://alert - triggers system alert
			DemoButton(
				title: "Alert",
				subtitle: "Show alert",
				icon: "exclamationmark.triangle",
				color: .red,
			) {
				navigationRouter.alert = NavigationRouter.AlertItem(
					title: "Demo Alert",
					message: "This is a demonstration of an alert via deep link",
					type: .warning,
				)
			}
		}
	}
}

#Preview {
	DemoButtonsView()
		.environmentObject(NavigationRouter())
		.padding()
}
