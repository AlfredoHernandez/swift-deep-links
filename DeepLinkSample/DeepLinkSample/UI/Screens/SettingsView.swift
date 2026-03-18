//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
	@Environment(\.dismiss) var onDismiss
	let section: String

	private var sectionTitle: String {
		switch section.lowercased() {
		case "account":
			"Account"

		case "notifications":
			"Notifications"

		case "privacy":
			"Privacy"

		case "security":
			"Security"

		case "appearance":
			"Appearance"

		case "language":
			"Language"

		default: section.capitalized
		}
	}

	private var sectionIcon: String {
		switch section.lowercased() {
		case "account":
			"person.circle"

		case "notifications":
			"bell.circle"

		case "privacy":
			"lock.circle"

		case "security":
			"shield.circle"

		case "appearance":
			"paintbrush.circle"

		case "language":
			"globe"

		default:
			"gearshape.circle"
		}
	}

	var body: some View {
		VStack(spacing: 20) {
			// Section Icon
			Image(systemName: sectionIcon)
				.font(.system(size: 60))
				.foregroundColor(.blue)

			Text(sectionTitle)
				.font(.title2)
				.fontWeight(.semibold)

			Text("\(sectionTitle) Settings")
				.font(.body)
				.foregroundColor(.secondary)
				.multilineTextAlignment(.center)

			// Mock Settings Options
			VStack(spacing: 12) {
				SettingsRow(title: "Option 1", icon: "gear")
				SettingsRow(title: "Option 2", icon: "slider.horizontal.3")
				SettingsRow(title: "Option 3", icon: "checkmark.circle")
			}
			.padding()
			.background(Color.gray.opacity(0.1))
			.cornerRadius(12)

			Spacer()

			Button("Close") {
				onDismiss()
			}
			.foregroundColor(.secondary)
		}
		.padding()
		.navigationTitle("Settings")
		.navigationBarTitleDisplayMode(.inline)
	}
}

private struct SettingsRow: View {
	let title: String
	let icon: String

	var body: some View {
		HStack {
			Image(systemName: icon)
				.foregroundColor(.blue)
				.frame(width: 20)

			Text(title)
				.font(.body)

			Spacer()

			Image(systemName: "chevron.right")
				.foregroundColor(.secondary)
				.font(.caption)
		}
		.padding(.vertical, 4)
	}
}

#Preview {
	NavigationView {
		SettingsView(section: "account")
	}
}
