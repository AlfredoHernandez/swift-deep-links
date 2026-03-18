//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// A reusable button component designed for demonstration purposes.
///
/// This component provides a consistent button design with:
/// - A colored icon on the left side
/// - A title and subtitle text layout
/// - A chevron indicator on the right
/// - Customizable colors and actions
///
/// The button uses a horizontal layout with proper spacing and follows
/// iOS design guidelines with rounded corners and subtle background.
///
/// - Parameters:
///   - title: The main text displayed on the button
///   - subtitle: The secondary text providing additional context
///   - icon: The SF Symbol name for the left-side icon
///   - color: The accent color for the icon and button styling
///   - action: The closure to execute when the button is tapped
struct DemoButton: View {
	let title: String
	let subtitle: String
	let icon: String
	let color: Color
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack {
				Image(systemName: icon)
					.font(.title2)
					.foregroundColor(color)
					.frame(width: 30)

				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.headline)
						.foregroundColor(.primary)
					Text(subtitle)
						.font(.caption)
						.foregroundColor(.secondary)
				}

				Spacer()

				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundColor(.secondary)
			}
			.padding()
			.background(Color.gray.opacity(0.1))
			.cornerRadius(12)
		}
		.buttonStyle(.plain)
	}
}

#Preview {
	VStack(spacing: 16) {
		DemoButton(
			title: "Information",
			subtitle: "Show information sheet",
			icon: "info.circle",
			color: .blue,
		) {
			print("Information tapped")
		}

		DemoButton(
			title: "User Profile",
			subtitle: "View user profile",
			icon: "person.circle",
			color: .green,
		) {
			print("Profile tapped")
		}

		DemoButton(
			title: "Product",
			subtitle: "View product details",
			icon: "bag.circle",
			color: .orange,
		) {
			print("Product tapped")
		}
	}
	.padding()
}
