//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import SwiftUI

/// A text field for opening any deep link through the app's coordinator,
/// showing why a link was rejected or failed.
struct CustomDeepLinkTesterView: View {
	@Environment(DeepLinkViewModel.self) private var viewModel
	@State private var customDeepLink = ""
	@State private var failureMessage: String?

	var body: some View {
		VStack(spacing: 16) {
			Text("Custom Deep Link Tester")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)

			VStack(spacing: 12) {
				TextField("Enter a custom deep link", text: $customDeepLink)
					.textFieldStyle(.roundedBorder)
					.autocapitalization(.none)
					.disableAutocorrection(true)

				HStack(spacing: 12) {
					Button("Test Deep Link") {
						testCustomDeepLink()
					}
					.buttonStyle(.borderedProminent)
					.disabled(customDeepLink.isEmpty)

					Button("Clear") {
						customDeepLink = ""
					}
					.buttonStyle(.bordered)
				}
			}
			.padding()
			.background(Color.gray.opacity(0.05))
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(Color.blue.opacity(0.3), lineWidth: 1),
			)
		}
		.alert("Deep Link Error", isPresented: Binding(get: { failureMessage != nil }, set: {
			if !$0 {
				failureMessage = nil
			}
		})) {
			Button("OK") {}
		} message: {
			Text(failureMessage ?? "")
		}
	}

	/// Opens the typed link through the app's coordinator, so it passes the
	/// same security checks as a link from another app.
	private func testCustomDeepLink() {
		guard let url = URL(string: customDeepLink) else {
			failureMessage = "This is not a valid URL."
			return
		}

		Task {
			let result = await viewModel.open(url)
			if result?.wasSuccessful != true {
				failureMessage = LinkOutcomeText.describe(result)
			}
		}
	}
}

#Preview {
	let viewModel = DeepLinkViewModel()
	CustomDeepLinkTesterView()
		.environment(viewModel)
		.padding()
}
