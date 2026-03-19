//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import OSLog

/// ViewModel for managing deep link processing and app state.
///
/// This ViewModel follows the MVVM pattern and uses the Observation framework
/// for reactive state management. It handles all deep link processing logic
/// and provides a clean interface for the UI layer.
///
/// ## Responsibilities:
/// - Deep link coordinator configuration and management
/// - Deep link processing pipeline execution
/// - Result logging and state management
/// - Error handling and recovery
@Observable
final class DeepLinkViewModel {
	// MARK: - Private Properties

	private let deepLinkService: DeepLinkService
	private let logger = Logger(subsystem: "swift-deep-link-sample-app", category: "DeepLinkViewModel")
	private var processingTask: Task<Void, Never>?
	private var coordinator: CoordinatorOf<AppRoute>?

	// MARK: - Public Properties

	/// The centralized navigation router that manages all navigation state
	let navigationRouter = NavigationRouter()

	/// Current processing state for UI feedback
	var isProcessing = false

	/// Last processing result for debugging/display
	var lastResult: ResultOf<AppRoute>?

	/// Processing error for user feedback
	var processingError: Error?

	// MARK: - Initialization

	init() {
		deepLinkService = DeepLinkService(navigationRouter: navigationRouter)
	}

	// MARK: - Public Interface

	/// Processes a deep link URL through the complete pipeline.
	///
	/// Cancels any in-flight processing before starting the new one.
	/// The task is tracked internally so it can be cancelled if a new
	/// deep link arrives before the previous one finishes.
	///
	/// - Parameter url: The deep link URL to process
	func processDeepLink(url: URL) {
		processingTask?.cancel()
		processingTask = Task { @MainActor in
			isProcessing = true
			processingError = nil

			do {
				let coordinator = try await getOrCreateCoordinator()
				let result = await coordinator.handle(url: url)

				guard !Task.isCancelled else { return }

				lastResult = result
				logResult(result)

				if !result.wasSuccessful {
					processingError = result.errors.first
				}
			} catch {
				guard !Task.isCancelled else { return }
				processingError = error
				logger.error("Failed to process deep link: \(error)")
			}

			isProcessing = false
		}
	}

	/// Clears the current processing error.
	@MainActor
	func clearError() {
		processingError = nil
	}

	/// Resets the processing state and clears all cached data.
	@MainActor
	func reset() {
		processingTask?.cancel()
		processingTask = nil
		coordinator = nil
		isProcessing = false
		lastResult = nil
		processingError = nil
	}
}

// MARK: - Private Methods

private extension DeepLinkViewModel {
	func getOrCreateCoordinator() async throws -> CoordinatorOf<AppRoute> {
		if let coordinator {
			return coordinator
		}
		let newCoordinator = try await deepLinkService.createCoordinator()
		coordinator = newCoordinator
		return newCoordinator
	}

	func logResult(_ result: ResultOf<AppRoute>) {
		let status = result.wasSuccessful ? "success" : "failed"
		let routes = result.routes.map(\.id).joined(separator: ", ")

		logger.info("Deep link processed: \(result.originalURL.absoluteString) [\(status)] routes=[\(routes)] time=\(String(format: "%.3f", result.executionTime))s")

		if result.hasErrors {
			for error in result.errors {
				logger.error("Deep link error: \(error.localizedDescription)")
			}
		}
	}
}
