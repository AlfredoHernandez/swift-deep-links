//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Combine
import DeepLink
import Foundation
import Observation
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

    /// Creates a new DeepLinkViewModel with the specified deep link service.
    ///
    /// - Parameter deepLinkService: The service responsible for deep link processing
    init(deepLinkService: DeepLinkService = DeepLinkService()) {
        self.deepLinkService = deepLinkService
    }

    // MARK: - Public Interface

    /// Processes a deep link URL through the complete pipeline.
    ///
    /// This method handles the entire deep link processing flow including:
    /// - Coordinator creation and configuration
    /// - URL processing through middleware
    /// - Route execution
    /// - Result handling and logging
    ///
    /// - Parameter url: The deep link URL to process
    @MainActor
    func processDeepLink(url: URL) async {
        isProcessing = true
        processingError = nil

        do {
            let coordinator = try await deepLinkService.createCoordinator(navigationRouter: navigationRouter)
            let result = await coordinator.handle(url: url)

            lastResult = result
            logDeepLinkResult(result)

            if !result.wasSuccessful {
                processingError = DeepLinkError.routeNotFound("Deep link processing failed")
            }
        } catch {
            processingError = error
            logger.error("Failed to process deep link: \(error)")
        }

        isProcessing = false
    }

    /// Clears the current processing error.
    @MainActor
    func clearError() {
        processingError = nil
    }

    /// Resets the processing state and clears all cached data.
    @MainActor
    func reset() {
        isProcessing = false
        lastResult = nil
        processingError = nil
    }
}

// MARK: - Private Methods

private extension DeepLinkViewModel {
    /// Logs detailed information about the deep link processing result.
    ///
    /// This method provides comprehensive logging of the deep link processing result,
    /// including success/failure status, routes processed, execution time, and any errors.
    /// The logs are formatted for easy reading in the console and include emojis for
    /// quick visual identification of the processing status.
    ///
    /// - Parameter result: The result of the deep link processing
    func logDeepLinkResult(_ result: ResultOf<AppRoute>) {
        let separator = String(repeating: "=", count: 50)
        print("\n" + separator)
        print("🔗 DEEP LINK PROCESSING RESULT")
        print(separator)

        // Basic information
        print("📱 Original URL: \(result.originalURL.absoluteString)")
        if let processedURL = result.processedURL {
            print("⚙️  Processed URL: \(processedURL.absoluteString)")
        } else {
            print("⚠️  Processed URL: nil (stopped by middleware)")
        }

        // Processing status
        if result.wasSuccessful {
            print("✅ Status: SUCCESS")
        } else {
            print("❌ Status: FAILED")
        }

        // Routes information
        print("🛣️  Routes Found: \(result.routes.count)")
        if !result.routes.isEmpty {
            for (index, route) in result.routes.enumerated() {
                print("   \(index + 1). \(route.id)")
            }
        }

        // Execution metrics
        print("⏱️  Execution Time: \(String(format: "%.3f", result.executionTime))s")
        print("✅ Successful Routes: \(result.successfulRoutes)")
        print("❌ Failed Routes: \(result.failedRoutes)")

        // Errors
        if result.hasErrors {
            print("🚨 Errors (\(result.errors.count)):")
            for (index, error) in result.errors.enumerated() {
                print("   \(index + 1). \(error.localizedDescription)")
            }
        } else {
            print("✨ No Errors")
        }

        // Summary
        print("📋 Summary: \(result.summary)")
        print(separator + "\n")
    }
}
