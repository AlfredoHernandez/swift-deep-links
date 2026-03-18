//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// A card component that displays deep link examples with copy functionality.
///
/// This component provides a clean way to showcase deep link URLs with:
/// - A colored indicator dot for visual categorization
/// - The deep link title with medium font weight
/// - The full URL displayed in a secondary color
/// - A copy button that changes state when clicked
/// - Visual feedback with animations and alerts
///
/// The card uses a bordered design with subtle background and follows
/// iOS design patterns for interactive elements.
///
/// - Parameters:
///   - title: The name/title of the deep link example
///   - url: The complete deep link URL to display and copy
///   - color: The accent color for the indicator dot and copy button
struct DeepLinkExampleCard: View {
	let title: String
	let url: String
	let color: Color

	@State private var showingCopiedAlert = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Circle()
					.fill(color)
					.frame(width: 8, height: 8)

				Text(title)
					.font(.subheadline)
					.fontWeight(.medium)

				Spacer()

				// Copy deep link URL to clipboard for testing
				Button(action: copyToClipboard) {
					HStack(spacing: 4) {
						Image(systemName: showingCopiedAlert ? "checkmark.circle.fill" : "doc.on.doc")
							.font(.caption)
						Text(showingCopiedAlert ? "Copiado" : "Copiar")
							.font(.caption2)
					}
					.foregroundColor(showingCopiedAlert ? .green : color)
				}
				.buttonStyle(.plain)
			}

			// Deep link URL format for external testing
			Text(url)
				.font(.caption)
				.foregroundColor(.secondary)
				.padding(.leading, 16)
		}
		.padding()
		.background(Color.gray.opacity(0.05))
		.cornerRadius(8)
		.overlay(
			RoundedRectangle(cornerRadius: 8)
				.stroke(color.opacity(0.3), lineWidth: 1),
		)
		.alert("Copied", isPresented: $showingCopiedAlert) {
			Button("OK") {}
		} message: {
			Text("The deep link has been copied to the clipboard")
		}
	}

	/// Copies the deep link URL to the system clipboard for external testing.
	///
	/// This method enables developers to test deep links in external apps (Safari, Notes, etc.)
	/// by copying the URL format to the clipboard with visual feedback.
	private func copyToClipboard() {
		UIPasteboard.general.string = url

		withAnimation(.easeInOut(duration: 0.2)) {
			showingCopiedAlert = true
		}

		// Reset the alert after 2 seconds
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
			withAnimation(.easeInOut(duration: 0.2)) {
				showingCopiedAlert = false
			}
		}
	}
}

#Preview {
	VStack(spacing: 12) {
		DeepLinkExampleCard(
			title: "Information",
			url: "deeplink://info?title=News&brief=News description",
			color: .blue,
		)

		DeepLinkExampleCard(
			title: "Profile",
			url: "deeplink://profile?userId=123&name=John Doe",
			color: .green,
		)

		DeepLinkExampleCard(
			title: "Product",
			url: "deeplink://product?productId=PROD-001&category=Electronics",
			color: .orange,
		)
	}
	.padding()
}
