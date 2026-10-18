//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct SecureDeepLinkTests {
	private let dates = ManualDateProvider()
	private let handler = CollectingHandler<AppRoute>()
	private let authentication = SampleAuthenticationProvider()
	private let pendingLinks: InMemoryPendingLinkStore
	private let confirmation = CollectingConfirmation(approves: true)

	init() {
		pendingLinks = InMemoryPendingLinkStore(dateProvider: dates.dateProvider)
	}

	// MARK: - Secure Defaults

	@Test
	func `Rejects a scheme the app does not declare`() async throws {
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: #require(URL(string: "testapp://product?productID=1")))

		#expect(result.firstDeepLinkError?.securityViolationReason == .unauthorizedScheme)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `Rejects a host the app does not route`() async throws {
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: #require(URL(string: "deeplink://admin")))

		#expect(result.firstDeepLinkError?.securityViolationReason == .unauthorizedHost)
	}

	// MARK: - Signed Links

	@Test
	func `Opens a signed reset link`() async throws {
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: sut.service.signedResetLink(userID: "42"))

		#expect(result.wasSuccessful)
		#expect(handler.handledRoutes.map(\.id) == [SecureActionParser.resetRoute(userID: "42").id])
	}

	@Test
	func `Rejects an unsigned reset link`() async throws {
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: #require(URL(string: "deeplink://reset?user=42")))

		#expect(result.firstDeepLinkError?.securityViolationReason == .missingSignature)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `Drops a signed link opened twice inside the replay window`() async throws {
		let sut = try makeSUT()
		let link = try sut.service.signedResetLink(userID: "42")

		_ = await sut.coordinator.handle(url: link)
		let replay = await sut.coordinator.handle(url: link)

		#expect(replay.wasStoppedByMiddleware)
		#expect(replay.errors.isEmpty)
	}

	@Test
	func `Rejects a signed link reused after the replay window`() async throws {
		let sut = try makeSUT()
		let link = try sut.service.signedResetLink(userID: "42")

		_ = await sut.coordinator.handle(url: link)
		dates.advance(by: 5)
		let reuse = await sut.coordinator.handle(url: link)

		#expect(reuse.firstDeepLinkError?.securityViolationReason == .reusedNonce)
	}

	// MARK: - Confirmation

	@Test
	func `Asks before opening a payment link`() async throws {
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: #require(URL(string: "deeplink://pay?amount=25")))

		#expect(result.wasSuccessful)
		#expect(confirmation.requests.count == 1)
	}

	@Test
	func `Does not open a payment link the user declines`() async throws {
		confirmation.approves = false
		let sut = try makeSUT()

		let result = try await sut.coordinator.handle(url: #require(URL(string: "deeplink://pay?amount=25")))

		#expect(try result.firstDeepLinkError == .confirmationDenied(#require(URL(string: "deeplink://pay?amount=25"))))
		#expect(handler.handledRoutes.isEmpty)
	}

	// MARK: - Resume After Sign-In

	@Test
	func `Saves an account link opened while signed out`() async throws {
		authentication.setAuthentication(false)
		let sut = try makeSUT()
		let url = try #require(URL(string: "deeplink://account"))

		let result = await sut.coordinator.handle(url: url, context: .openedURL(url))

		#expect(result.firstDeepLinkError == .unauthorizedAccess(url))
		#expect(await pendingLinks.takeAll() == [url])
	}

	@Test
	func `Resumes the saved account link after sign-in and confirms it first`() async throws {
		authentication.setAuthentication(false)
		let sut = try makeSUT()
		let url = try #require(URL(string: "deeplink://account"))
		_ = await sut.coordinator.handle(url: url, context: .openedURL(url))
		dates.advance(by: 5)

		authentication.setAuthentication(true)
		let resumed = await sut.coordinator.resumePendingLinks(from: pendingLinks)

		#expect(resumed.map(\.wasSuccessful) == [true])
		#expect(confirmation.requests.map(\.context.isResumedPendingLink) == [true])
		#expect(handler.handledRoutes.map(\.id) == [SecureActionParser.accountRoute.id])
	}

	// MARK: - Helpers

	private func makeSUT() throws -> (service: DeepLinkService, coordinator: DeepLinkCoordinator<AppRoute>) {
		let service = DeepLinkService(
			handler: handler,
			confirmationProvider: confirmation,
			authenticationProvider: authentication,
			pendingLinks: pendingLinks,
			nonceStore: InMemoryNonceStore(dateProvider: dates.dateProvider),
			rateLimitPersistence: InMemoryRateLimitPersistence(),
			delegates: [],
			dateProvider: dates.dateProvider,
		)
		return try (service, service.makeCoordinator())
	}
}
