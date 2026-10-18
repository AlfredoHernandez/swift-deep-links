//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation
import OSLog

/// Owns the app's navigation state and its deep link coordinator.
///
/// Links from other apps arrive through `.onDeepLink(coordinator)`, which tags
/// each one with its source. In-app demo buttons call ``open(_:)``, which tags
/// the link as a custom-scheme link the same way. ``logResults()`` logs every
/// result with URLs and errors redacted.
@Observable
final class DeepLinkViewModel {
	private static let logger = Logger(subsystem: "swift-deep-link-sample-app", category: "DeepLinkViewModel")

	let navigationRouter: NavigationRouter
	let confirmationPrompter: ConfirmationPrompter
	let secureShowcase: SecureShowcaseViewModel

	/// `nil` only if the configuration is invalid, which is logged.
	let coordinator: DeepLinkCoordinator<AppRoute>?

	private(set) var lastResult: DeepLinkResult<AppRoute>?

	init() {
		let navigationRouter = NavigationRouter()
		let confirmationPrompter = ConfirmationPrompter()
		let service = DeepLinkService.live(navigationRouter: navigationRouter, confirmationProvider: confirmationPrompter)
		let coordinator = Self.makeCoordinator(with: service)

		self.navigationRouter = navigationRouter
		self.confirmationPrompter = confirmationPrompter
		self.coordinator = coordinator
		secureShowcase = SecureShowcaseViewModel(service: service, coordinator: coordinator)
	}

	/// Opens `url` as if another app had opened it.
	@discardableResult
	func open(_ url: URL) async -> DeepLinkResult<AppRoute>? {
		await coordinator?.handle(url: url, context: .openedURL(url))
	}

	/// Logs every result, redacted, for as long as the calling task runs.
	func logResults() async {
		guard let coordinator else { return }
		for await result in coordinator.results {
			lastResult = result
			Self.log(result)
		}
	}
}

// MARK: - Private Methods

private extension DeepLinkViewModel {
	static func makeCoordinator(with service: DeepLinkService) -> DeepLinkCoordinator<AppRoute>? {
		do {
			return try service.makeCoordinator()
		} catch {
			logger.error("Deep links are unavailable: \(DeepLinkLogPrivacy.redacted.describe(error))")
			return nil
		}
	}

	static func log(_ result: DeepLinkResult<AppRoute>) {
		let privacy = DeepLinkLogPrivacy.redacted
		let routes = result.routes.map(\.id).joined(separator: ", ")
		logger.info("Deep link \(privacy.describe(result.originalURL)): \(LinkOutcomeText.describe(result)) routes=[\(routes)]")

		for error in result.errors {
			logger.error("Deep link error: \(privacy.describe(error))")
		}
	}
}
