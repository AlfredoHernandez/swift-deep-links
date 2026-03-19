//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

struct DeepLinkInstructionsView: View {
	@Environment(\.dismiss) var dismiss

	var body: some View {
		NavigationView {
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					// Header
					VStack(spacing: 8) {
						Image(systemName: "questionmark.circle.fill")
							.font(.system(size: 50))
							.foregroundColor(.blue)

						Text("How to Use Deep Links")
							.font(.title2)
							.fontWeight(.bold)
					}
					.frame(maxWidth: .infinity)
					.padding(.top)

					// Instructions
					VStack(alignment: .leading, spacing: 16) {
						InstructionSection(
							title: "1. Copy Examples",
							icon: "doc.on.doc",
							description: "Tap the 'Copy' button on any example card to copy the deep link to the clipboard.",
							color: .blue,
						)

						InstructionSection(
							title: "2. Test Deep Links",
							icon: "link",
							description: "Use the text field in 'Custom Deep Link Tester' to test your own custom deep links.",
							color: .green,
						)

						InstructionSection(
							title: "3. iOS Simulator",
							icon: "iphone",
							description: "In the iOS Simulator, use the Device > Photos menu to open Safari and paste the deep links.",
							color: .orange,
						)

						InstructionSection(
							title: "4. Real Device",
							icon: "iphone.gen3",
							description: "Send the deep links via message, email or use them in Safari to test them on your device.",
							color: .purple,
						)
					}

					// Examples
					VStack(alignment: .leading, spacing: 12) {
						Text("Usage Examples")
							.font(.headline)

						Text("• Copy a deep link and paste it in Safari")
						Text("• Send the deep link via message to your device")
						Text("• Use the Simulator to open Safari from Photos")
						Text("• Test variations by modifying the parameters")
					}
					.padding()
					.background(Color.gray.opacity(0.1))
					.cornerRadius(12)

					Spacer(minLength: 20)
				}
				.padding()
			}
			.navigationTitle("Instructions")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .navigationBarTrailing) {
					Button("Close") {
						dismiss()
					}
				}
			}
		}
	}
}

private struct InstructionSection: View {
	let title: String
	let icon: String
	let description: String
	let color: Color

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: icon)
				.font(.title2)
				.foregroundColor(color)
				.frame(width: 30)

			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.headline)

				Text(description)
					.font(.body)
					.foregroundColor(.secondary)
			}

			Spacer()
		}
		.padding()
		.background(Color.gray.opacity(0.05))
		.cornerRadius(12)
	}
}

#Preview {
	DeepLinkInstructionsView()
}
