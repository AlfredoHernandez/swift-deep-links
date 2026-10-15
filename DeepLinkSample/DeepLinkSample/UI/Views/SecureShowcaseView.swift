//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import SwiftUI

/// Shows the security stages of the sample's chain: a signed link, a
/// confirmation prompt, resume after sign-in and, in debug builds,
/// `DeepLinkDiagnostics`.
struct SecureShowcaseView: View {
	@Environment(SecureShowcaseViewModel.self) private var viewModel

	var body: some View {
		VStack(spacing: 16) {
			Text("Secure Links")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)

			VStack(alignment: .leading, spacing: 12) {
				signedLinkSection
				Divider()
				confirmationSection
				Divider()
				signInSection
				#if DEBUG
				Divider()
				diagnosticsSection
				#endif
				outcome
			}
			.padding()
			.background(Color.gray.opacity(0.05))
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(Color.green.opacity(0.3), lineWidth: 1),
			)
		}
	}

	// MARK: - Sections

	private var signedLinkSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			caption("deeplink://reset needs a signature, an expiry and a single-use nonce.")
			HStack(spacing: 8) {
				action("Signed", systemImage: "signature") { await viewModel.openSignedResetLink() }
				action("Again", systemImage: "arrow.clockwise") { await viewModel.reopenSignedLink() }
					.disabled(!viewModel.canReopenSignedLink)
				action("Unsigned", systemImage: "xmark.seal") { await viewModel.openUnsignedResetLink() }
			}
		}
	}

	private var confirmationSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			caption("deeplink://pay asks you before it opens.")
			action("Open payment link", systemImage: "creditcard") { await viewModel.openPaymentLink() }
		}
	}

	private var signInSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			caption(viewModel.isSignedIn
				? "Signed in. Sign out, open the account link, then sign in to resume it."
				: "Signed out. The account link is saved and resumes, with a confirmation, after sign-in.")
			HStack(spacing: 8) {
				action("Account link", systemImage: "person.crop.circle") { await viewModel.openAccountLink() }
				if viewModel.isSignedIn {
					action("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { await viewModel.signOut() }
				} else {
					action("Sign in", systemImage: "key") { await viewModel.signIn() }
				}
			}
		}
	}

	#if DEBUG
	private var diagnosticsSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			caption("Debug builds only: compare the configuration with Info.plist and the parsers.")
			action("Check configuration", systemImage: "stethoscope") { await viewModel.runDiagnostics() }
			if let messages = viewModel.diagnosticMessages {
				Text(messages.isEmpty ? "No warnings." : messages.joined(separator: "\n"))
					.font(.caption)
					.foregroundColor(messages.isEmpty ? .green : .orange)
			}
		}
	}
	#endif

	@ViewBuilder
	private var outcome: some View {
		if let outcome = viewModel.outcome {
			Text(outcome)
				.font(.caption)
				.fontWeight(.semibold)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	// MARK: - Helpers

	private func caption(_ text: String) -> some View {
		Text(text)
			.font(.caption)
			.foregroundColor(.secondary)
	}

	private func action(_ title: String, systemImage: String, perform: @escaping () async -> Void) -> some View {
		Button {
			Task { await perform() }
		} label: {
			Label(title, systemImage: systemImage)
				.font(.caption)
				.frame(maxWidth: .infinity)
		}
		.buttonStyle(.bordered)
		.tint(.green)
	}
}
