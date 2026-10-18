//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct ReadinessShowcaseViewModelTests {
	private let router = NavigationRouter()

	@Test
	func `A link sent before the app is ready is queued, not routed`() async {
		let sut = makeSUT()

		await sut.sendDeepLink(host: "settings", params: "section=account", navigationRouter: router)

		#expect(sut.pendingCount == 1)
		#expect(sut.queuedLinks.count == 1)
		#expect(router.stack.isEmpty)
	}

	@Test
	func `Marking ready drains the queued links through the coordinator`() async {
		let sut = makeSUT()
		await sut.sendDeepLink(host: "settings", params: "section=account", navigationRouter: router)

		await sut.markReady(navigationRouter: router)

		#expect(sut.isReady)
		#expect(sut.pendingCount == 0)
		#expect(sut.queuedLinks.isEmpty)
		#expect(router.stack == [.settings(section: "account")])
	}

	@Test
	func `A link sent once the app is ready is routed at once`() async {
		let sut = makeSUT()
		await sut.markReady(navigationRouter: router)

		await sut.sendDeepLink(host: "settings", params: "section=privacy", navigationRouter: router)

		#expect(sut.pendingCount == 0)
		#expect(router.stack == [.settings(section: "privacy")])
	}

	@Test
	func `A link the security check rejects is never queued`() async {
		let sut = makeSUT()

		await sut.sendDeepLink(host: "admin", params: "x=1", navigationRouter: router)

		#expect(sut.pendingCount == 0)
	}

	@Test
	func `Queued links are shown redacted`() async {
		let sut = makeSUT()

		await sut.sendDeepLink(host: "info", params: "title=Reset&brief=x&token=secret", navigationRouter: router)

		#expect(sut.queuedLinks.first?.contains("secret") == false)
	}

	@Test
	func `Reset gates the queue again`() async {
		let sut = makeSUT()
		await sut.markReady(navigationRouter: router)

		sut.resetQueue()

		#expect(!sut.isReady)
	}

	// MARK: - Helpers

	private func makeSUT() -> ReadinessShowcaseViewModel {
		ReadinessShowcaseViewModel(rateLimitPersistence: InMemoryRateLimitPersistence())
	}
}
