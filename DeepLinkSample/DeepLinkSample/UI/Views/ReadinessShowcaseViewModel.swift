//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import Observation
import OSLog

/// ViewModel that manages the readiness middleware showcase state.
///
/// Demonstrates how `DeepLinkReadinessQueue` queues URLs when the app
/// is not ready, drains them on `markReady()`, and supports `reset()`
/// for logout/login cycles.
@Observable
final class ReadinessShowcaseViewModel {
	// MARK: - Private Properties

	private let logger = Logger(subsystem: "swift-deep-link-sample-app", category: "ReadinessShowcase")
	private let queue = DeepLinkReadinessQueue(maxQueueSize: 10)
	private var drainDelay: Duration
	private var coordinator: CoordinatorOf<AppRoute>?

	// MARK: - Initialization

	/// Creates a new showcase view model.
	///
	/// - Parameter drainDelay: The delay between processing each queued URL. Defaults to zero.
	init(drainDelay: Duration = .zero) {
		self.drainDelay = drainDelay
	}

	// MARK: - Public State

	/// Whether the readiness queue is currently in the ready state
	private(set) var isReady = false

	/// Number of URLs pending in the queue
	private(set) var pendingCount = 0

	/// URLs currently queued for display purposes
	private(set) var queuedURLs: [URL] = []

	/// Configurable delay (in seconds) between processing each queued URL
	var drainDelaySeconds: Double = 0 {
		didSet { drainDelay = .milliseconds(Int(drainDelaySeconds * 1000)) }
	}

	// MARK: - Public Interface

	/// Queues a random deep link from a variety of route types.
	///
	/// Generates a randomized product, info, settings, or profile deep link
	/// to demonstrate that different URLs are queued and processed independently.
	func queueRandomDeepLink() {
		let deepLink = Self.randomDeepLinks.randomElement()!
		sendDeepLink(host: deepLink.host, params: deepLink.params)
	}

	/// Sends a deep link URL through the readiness middleware.
	///
	/// If the queue is not ready, the URL is stored and the pending
	/// count is updated. If ready, the URL passes through immediately.
	///
	/// - Parameters:
	///   - host: The deep link host (e.g., "product", "info")
	///   - params: The query parameters string
	func sendDeepLink(host: String, params: String) {
		guard let url = URL(string: "deeplink://\(host)?\(params)") else { return }

		let result = queue.enqueue(url)

		if result == nil {
			queuedURLs.append(url)
			logger.info("URL queued (not ready): \(url.absoluteString)")
		} else {
			logger.info("URL passed through (ready): \(url.absoluteString)")
		}

		syncState()
	}

	/// Marks the queue as ready, drains pending URLs, and processes them
	/// through the coordinator.
	///
	/// - Parameter navigationRouter: The router for handling navigation actions
	func markReady(navigationRouter: NavigationRouter) {
		let pending = queue.markReady()
		queuedURLs = []
		syncState()

		logger.info("Queue marked ready. Draining \(pending.count) URLs.")

		guard !pending.isEmpty else { return }

		Task { @MainActor in
			let coordinator = await getOrCreateCoordinator(navigationRouter: navigationRouter)

			for (index, url) in pending.enumerated() {
				logger.info("Processing queued URL: \(url.absoluteString)")
				await coordinator.handle(url: url)

				if index < pending.count - 1 {
					try? await Task.sleep(for: drainDelay)
				}
			}
		}
	}

	/// Resets the queue to its not-ready state, simulating a logout/login cycle.
	func resetQueue() {
		queue.reset()
		queuedURLs = []
		syncState()
		logger.info("Queue reset to not-ready state")
	}
}

// MARK: - Private Methods

private extension ReadinessShowcaseViewModel {
	struct RandomDeepLink {
		let host: String
		let params: String
	}

	static let randomDeepLinks: [RandomDeepLink] = [
		RandomDeepLink(host: "product", params: "productID=PROD-\(Int.random(in: 100 ... 999))&category=Electronics"),
		RandomDeepLink(host: "product", params: "productID=PROD-\(Int.random(in: 100 ... 999))&category=Clothing"),
		RandomDeepLink(host: "product", params: "productID=PROD-\(Int.random(in: 100 ... 999))&category=Books"),
		RandomDeepLink(host: "info", params: "title=Welcome&brief=Thanks for joining us"),
		RandomDeepLink(host: "info", params: "title=Sale&brief=50 percent off all items"),
		RandomDeepLink(host: "info", params: "title=Update&brief=New version available"),
		RandomDeepLink(host: "settings", params: "section=account"),
		RandomDeepLink(host: "settings", params: "section=notifications"),
		RandomDeepLink(host: "settings", params: "section=privacy"),
		RandomDeepLink(host: "alert", params: "title=Reminder&message=Check your inbox&type=info"),
		RandomDeepLink(host: "alert", params: "title=Warning&message=Storage almost full&type=warning"),
		RandomDeepLink(host: "alert", params: "title=Success&message=Order confirmed&type=success"),
	]

	func syncState() {
		isReady = queue.isReady
		pendingCount = queue.pendingCount
	}

	func getOrCreateCoordinator(navigationRouter: NavigationRouter) async -> CoordinatorOf<AppRoute> {
		if let coordinator { return coordinator }

		let parsers: [any DeepLinkParser<AppRoute>] = [
			InformationParser(),
			ProfileParser(),
			ProductParser(),
			SettingsParser(),
			AlertParser(),
		]

		let routing = DefaultDeepLinkRouting<AppRoute>(parsers: parsers)
		let handler = AppDeepLinkHandler(navigationRouter: navigationRouter)

		let newCoordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			routeExecutionDelay: .milliseconds(250),
		)

		coordinator = newCoordinator
		return newCoordinator
	}
}
