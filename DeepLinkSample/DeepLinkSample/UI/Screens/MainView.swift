//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// The main screen of the Deep Link Sample App.
///
/// This view serves as the central hub for demonstrating deep link functionality.
/// It combines multiple UI components to provide a comprehensive testing and
/// demonstration environment for deep link capabilities.
///
/// ## Features:
/// - **Header section**: App title and description
/// - **Demo buttons**: Interactive buttons to test different navigation patterns
/// - **Deep link examples**: Copyable examples of all supported URL formats
/// - **Custom tester**: Manual testing interface for custom deep links
/// - **Help system**: Instructions and guidance for users
///
/// ## Navigation Architecture:
/// The view implements a complete navigation system supporting:
/// - **NavigationStack**: For stack-based navigation (Product, Settings)
/// - **Sheet presentations**: For modal views (Information, Profile)
/// - **Alert presentations**: For system alerts and notifications
///
/// ## Deep Link Integration:
/// The view is designed to handle incoming deep links through the `NavigationRouter`
/// and provides immediate visual feedback for all navigation actions.
struct MainView: View {
	@EnvironmentObject var navigationRouter: NavigationRouter
	@State private var showingInstructions = false

	var body: some View {
		NavigationStack(path: $navigationRouter.stack) {
			ScrollView {
				VStack(spacing: 24) {
					HeaderView()
					DemoButtonsView()
					DeepLinkExamplesView()
					CustomDeepLinkTesterView()
				}
				.padding()
			}
			.navigationTitle("Deep Links")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button(action: { showingInstructions = true }) {
						Image(systemName: "questionmark.circle")
					}
				}
			}
			// Deep link navigation destinations
			.navigationDestination(for: Stack.self, destination: { route in
				switch route {
				case let .product(productID, category):
					ProductView(productID: productID, category: category)

				case let .settings(section):
					SettingsView(section: section)
				}
			})
		}
		// Deep link sheet presentations
		.sheet(item: $navigationRouter.sheet) { sheet in
			NavigationView {
				switch sheet {
				case let .info(title, brief):
					InformationView(infoTitle: title, infoBrief: brief)

				case let .profile(userID, name):
					ProfileView(userID: userID, name: name)
				}
			}
		}
		// Deep link alert presentations
		.alert(item: $navigationRouter.alert) { alert in
			SwiftUI.Alert(
				title: Text(alert.title),
				message: Text(alert.message),
				dismissButton: .default(Text("OK")),
			)
		}
		.sheet(isPresented: $showingInstructions) {
			DeepLinkInstructionsView()
		}
	}
}

#Preview {
	MainView()
		.environmentObject(NavigationRouter())
}
