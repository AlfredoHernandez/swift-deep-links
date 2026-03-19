//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import SwiftUI

/// A view that showcases the Readiness Middleware functionality.
///
/// This view demonstrates how deep links are queued when the app
/// is not ready and automatically drained when readiness is signaled.
///
/// ## Features:
/// - Toggle to simulate app readiness state
/// - Send deep links while not ready (queued)
/// - Drain and process queued deep links on "Mark Ready"
/// - Visual feedback of pending queue count
/// - Reset to simulate logout/login cycles
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
				drainDelayPicker
				queuedURLsList
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

	private var queuedURLsList: some View {
		Group {
			if !viewModel.queuedURLs.isEmpty {
				VStack(alignment: .leading, spacing: 4) {
					ForEach(viewModel.queuedURLs, id: \.absoluteString) { url in
						HStack(spacing: 6) {
							Image(systemName: "link")
								.font(.caption2)
								.foregroundColor(.orange)
							Text(url.absoluteString)
								.font(.caption)
								.foregroundColor(.secondary)
								.lineLimit(1)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}

	private var drainDelayPicker: some View {
		HStack {
			Text("Drain delay")
				.font(.caption)
				.foregroundColor(.secondary)
			Spacer()
			Picker("Delay", selection: $viewModel.drainDelaySeconds) {
				Text("0s").tag(0.0)
				Text("0.5s").tag(0.5)
				Text("1s").tag(1.0)
				Text("2s").tag(2.0)
			}
			.pickerStyle(.segmented)
			.frame(width: 200)
		}
	}

	private var actionButtons: some View {
		VStack(spacing: 8) {
			Button {
				viewModel.queueRandomDeepLink()
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
					viewModel.markReady(navigationRouter: navigationRouter)
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
