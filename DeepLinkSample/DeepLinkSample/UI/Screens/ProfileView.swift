//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
	@Environment(\.dismiss) var onDismiss
	let userID: String
	let name: String?

	var body: some View {
		VStack(spacing: 20) {
			// Profile Avatar
			Circle()
				.fill(Color.blue.gradient)
				.frame(width: 80, height: 80)
				.overlay {
					Text(name?.prefix(1).uppercased() ?? "U")
						.font(.largeTitle)
						.fontWeight(.bold)
						.foregroundColor(.white)
				}

			VStack(spacing: 8) {
				Text(name ?? "User")
					.font(.title2)
					.fontWeight(.semibold)

				Text("ID: \(userID)")
					.font(.caption)
					.foregroundColor(.secondary)
			}

			VStack(spacing: 12) {
				Button("View Full Profile") {
					// Simulate navigation to full profile
				}
				.buttonStyle(.borderedProminent)

				Button("Send Message") {
					// Simulate sending message
				}
				.buttonStyle(.bordered)
			}

			Spacer()

			Button("Close") {
				onDismiss()
			}
			.foregroundColor(.secondary)
		}
		.padding()
		.navigationTitle("Profile")
		.navigationBarTitleDisplayMode(.inline)
	}
}

#Preview {
	NavigationView {
		ProfileView(userID: "123", name: "John Doe")
	}
}
