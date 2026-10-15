//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import SwiftUI

/// The Deep Link Sample App.
///
/// `.onDeepLink(_:)` hands every link from another app to the coordinator
/// built by `DeepLinkService`, tagged with its source. The coordinator runs
/// the recommended chain (`secureDefaults`, signed links, authentication,
/// confirmation, analytics) and `DeepLinkViewModel` logs each result redacted.
@main
struct DeepLinkSampleApp: App {
	@State private var viewModel = DeepLinkViewModel()

	var body: some Scene {
		WindowGroup {
			MainView()
				.environment(viewModel.navigationRouter)
				.environment(viewModel)
				.environment(viewModel.secureShowcase)
				.deepLinkConfirmations(viewModel.confirmationPrompter)
				.onDeepLink(viewModel.coordinator)
				.task { await viewModel.logResults() }
		}
	}
}
