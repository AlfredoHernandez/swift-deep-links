//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// The main entry point of the Deep Link Sample App.
///
/// This app demonstrates a comprehensive deep link implementation using the DeepLink framework
/// with a modern MVVM architecture and the Observation framework for reactive state management.
/// It showcases different navigation patterns and provides a testing environment for
/// deep link functionality.
///
/// ## Features:
/// - **Complete deep link infrastructure**: Parsing, routing, and handling
/// - **Multiple navigation patterns**: Stack navigation, sheet presentations, and alerts
/// - **Interactive testing interface**: Demo buttons and custom URL testing
/// - **Comprehensive examples**: Copyable deep link URLs for all supported types
/// - **MVVM Architecture**: Clean separation of concerns with ViewModels
/// - **Reactive State Management**: Using Swift's Observation framework
///
/// ## Architecture:
/// The app follows the MVVM pattern with:
/// - **View**: SwiftUI views that observe the ViewModel
/// - **ViewModel**: `DeepLinkViewModel` manages app state and business logic
/// - **Service**: `DeepLinkService` handles deep link coordinator configuration
/// - **Providers**: Sample providers for authentication and analytics
@main
struct DeepLinkSampleApp: App {
	// MARK: - Properties

	/// The main ViewModel that manages app state and deep link processing
	@State private var viewModel = DeepLinkViewModel()

	// MARK: - Body

	var body: some Scene {
		WindowGroup {
			MainView()
				.environmentObject(viewModel.navigationRouter)
				.onOpenURL { url in
					Task {
						await viewModel.processDeepLink(url: url)
					}
				}
		}
	}
}
