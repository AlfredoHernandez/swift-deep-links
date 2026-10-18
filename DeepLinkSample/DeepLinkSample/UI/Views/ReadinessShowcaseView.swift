//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import SwiftUI

/// Shows `.readiness(queue:)`: links sent before the app is ready are queued
/// (shown redacted), "Mark Ready" drains them with `markReadyAndDrain(queue:)`,
/// and "Reset" gates the queue again, as after a sign-out.
struct ReadinessShowcaseView: View {
	@Environment(NavigationRouter.self) var navigationRouter
	@State private var viewModel = ReadinessShowcaseViewModel()

	var body: some View {
		VStack(spacing: 16) {
			Text("Readiness Middleware")
				.font(.headline)
				.frame(maxWidth: .infinity, alignment: .leading)

			VStack(spacing: 12) {
				statusBadge
				queuedLinksList
				actionButtons
			}
			.padding()
			.background(Color.gray.opacity(0.05))
			.cornerRadius(12)
			.overlay(
				RoundedRectangle(cornerRadius: 12)
					.stroke(Color.purple.opacity(0.3), lineWidth: 1),
			)
		}
	}

	// MARK: - Subviews

	private var statusBadge: some View {
		HStack {
			Image(systemName: viewModel.isReady ? "checkmark.circle.fill" : "clock.fill")
				.foregroundColor(viewModel.isReady ? .green : .orange)
			Text(viewModel.isReady ? "App Ready" : "App Not Ready")
				.font(.subheadline)
				.fontWeight(.semibold)
			Spacer()
			Text("\(viewModel.pendingCount) queued")
				.font(.caption)
				.foregroundColor(.secondary)
				.padding(.horizontal, 8)
				.padding(.vertical, 4)
				.background(Color.orange.opacity(viewModel.pendingCount > 0 ? 0.2 : 0.05))
				.cornerRadius(8)
		}
	}

	@ViewBuilder
	private var queuedLinksList: some View {
		if !viewModel.queuedLinks.isEmpty {
			VStack(alignment: .leading, spacing: 4) {
				ForEach(Array(viewModel.queuedLinks.enumerated()), id: \.offset) { _, link in
					HStack(spacing: 6) {
						Image(systemName: "link")
							.font(.caption2)
							.foregroundColor(.orange)
						Text(link)
							.font(.caption)
							.foregroundColor(.secondary)
							.lineLimit(1)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private var actionButtons: some View {
		VStack(spacing: 8) {
			Button {
				Task { await viewModel.queueRandomDeepLink(navigationRouter: navigationRouter) }
			} label: {
				Label("Queue Random Deep Link", systemImage: "shuffle.circle")
					.font(.caption)
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.tint(.purple)
			.disabled(viewModel.isReady)

			HStack(spacing: 8) {
				Button {
					Task { await viewModel.markReady(navigationRouter: navigationRouter) }
				} label: {
					Label("Mark Ready", systemImage: "checkmark.circle")
						.font(.caption)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.tint(.green)
				.disabled(viewModel.isReady)

				Button {
					viewModel.resetQueue()
				} label: {
					Label("Reset", systemImage: "arrow.counterclockwise")
						.font(.caption)
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.tint(.red)
				.disabled(!viewModel.isReady)
			}
		}
	}
}

#Preview {
	ReadinessShowcaseView()
		.environment(NavigationRouter())
		.padding()
}
