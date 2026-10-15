//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import Foundation
import Testing

@MainActor
struct LinkOutcomeTextTests {
	private nonisolated static let url = URL(string: "deeplink://reset?user=42&token=secret")!

	@Test
	func `A missing coordinator is reported as unavailable`() {
		#expect(LinkOutcomeText.describe(nil) == "Deep links are unavailable.")
	}

	@Test
	func `A successful link is reported as opened`() {
		#expect(LinkOutcomeText.describe(makeResult()) == "Opened.")
	}

	@Test
	func `A link stopped without an error is reported as stopped quietly`() {
		let text = LinkOutcomeText.describe(makeResult(processedURL: nil))

		#expect(text.hasPrefix("Stopped quietly"))
	}

	@Test(arguments: [
		(DeepLinkError.securityViolation("Missing link signature"), "missingSignature"),
		(.unauthorizedAccess(url), "sign in first"),
		(.confirmationDenied(url), "declined"),
		(.rateLimitExceeded(maxRequests: 1, timeWindow: 60), "too many links"),
	])
	func `A rejected link names the reason`(error: DeepLinkError, expected: String) {
		let text = LinkOutcomeText.describe(makeResult(errors: [error]))

		#expect(text.contains(expected))
	}

	@Test
	func `Other failures are described without secrets`() {
		let text = LinkOutcomeText.describe(makeResult(errors: [DeepLinkError.routeNotFound(Self.url)]))

		#expect(!text.contains("secret"))
	}

	// MARK: - Helpers

	private func makeResult(
		processedURL: URL? = LinkOutcomeTextTests.url,
		errors: [any Error] = [],
	) -> DeepLinkResult<AppRoute> {
		DeepLinkResult(
			originalURL: Self.url,
			processedURL: processedURL,
			routes: [],
			executionTime: 0,
			errors: errors,
		)
	}
}
