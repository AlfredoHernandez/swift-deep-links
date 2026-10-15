//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation
import Observation
import OSLog

/// Drives the readiness showcase with its own coordinator:
/// `secureDefaults` → `.readiness(queue:)`.
///
/// Links sent before the app is ready pass the security checks and wait in the
/// queue; ``markReady(navigationRouter:)`` calls `markReadyAndDrain(queue:)`,
/// which resumes each one right after the readiness gate, with the source it
/// arrived with. Queued links are shown and logged redacted.
@Observable
final class ReadinessShowcaseViewModel {
	private static let logger = Logger(subsystem: "swift-deep-link-sample-app", category: "ReadinessShowcase")

	private let queue = DeepLinkReadinessQueue(maxQueueSize: 10)
	private let rateLimitPersistence: (any RateLimitPersistence)?
	private var coordinator: DeepLinkCoordinator<AppRoute>?

	private(set) var isReady = false
	private(set) var pendingCount = 0

	/// The queued links, redacted.
	private(set) var queuedLinks: [String] = []

	init(rateLimitPersistence: (any RateLimitPersistence)? = nil) {
		self.rateLimitPersistence = rateLimitPersistence
	}

	func queueRandomDeepLink(navigationRouter: NavigationRouter) async {
		let deepLink = Self.randomDeepLink()
		await sendDeepLink(host: deepLink.host, params: deepLink.params, navigationRouter: navigationRouter)
	}

	func sendDeepLink(host: String, params: String, navigationRouter: NavigationRouter) async {
		guard let url = URL(string: "deeplink://\(host)?\(params)"),
		      let coordinator = coordinator(for: navigationRouter)
		else { return }

		let result = await coordinator.handle(url: url, context: .openedURL(url))
		Self.logger.info("\(DeepLinkLogPrivacy.redacted.describe(url)): \(LinkOutcomeText.describe(result))")
		syncState()
	}

	func markReady(navigationRouter: NavigationRouter) async {
		guard let coordinator = coordinator(for: navigationRouter) else { return }

		let drained = await coordinator.markReadyAndDrain(queue: queue)
		Self.logger.info("Queue marked ready. Drained \(drained.count) links.")
		syncState()
	}

	func resetQueue() {
		queue.reset()
		syncState()
		Self.logger.info("Queue reset to not-ready state")
	}
}

// MARK: - Private Methods

private extension ReadinessShowcaseViewModel {
	struct RandomDeepLink {
		let host: String
		let params: String
	}

	static func randomDeepLink() -> RandomDeepLink {
		let productID = "PROD-\(Int.random(in: 100 ... 999))"
		let choices = [
			RandomDeepLink(host: "product", params: "productID=\(productID)&category=Electronics"),
			RandomDeepLink(host: "product", params: "productID=\(productID)&category=Books"),
			RandomDeepLink(host: "info", params: "title=Welcome&brief=Thanks for joining us"),
			RandomDeepLink(host: "info", params: "title=Sale&brief=50 percent off all items"),
			RandomDeepLink(host: "settings", params: "section=notifications"),
			RandomDeepLink(host: "settings", params: "section=privacy"),
			RandomDeepLink(host: "alert", params: "title=Reminder&message=Check your inbox&type=info"),
			RandomDeepLink(host: "alert", params: "title=Success&message=Order confirmed&type=success"),
		]
		return choices.randomElement() ?? choices[0]
	}

	func syncState() {
		isReady = queue.isReady
		pendingCount = queue.pendingCount
		queuedLinks = queue.pendingURLs.map(DeepLinkLogPrivacy.redacted.describe)
	}

	func coordinator(for navigationRouter: NavigationRouter) -> DeepLinkCoordinator<AppRoute>? {
		if let coordinator {
			return coordinator
		}
		do {
			let newCoordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
				.parsers(DeepLinkService.parsers)
				.handler(AppDeepLinkHandler(navigationRouter: navigationRouter))
				.secureDefaults(
					allowedSchemes: DeepLinkService.allowedSchemes,
					allowedHosts: DeepLinkService.allowedHosts,
					rateLimitPersistence: rateLimitPersistence,
				)
				.middleware(.readiness(queue: queue))
				.build()
			coordinator = newCoordinator
			return newCoordinator
		} catch {
			Self.logger.error("Readiness showcase unavailable: \(DeepLinkLogPrivacy.redacted.describe(error))")
			return nil
		}
	}
}
