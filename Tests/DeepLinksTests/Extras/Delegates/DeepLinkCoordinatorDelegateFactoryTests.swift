//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct DeepLinkCoordinatorDelegateFactoryTests {
	private let sampleURL = URL(string: "myapp://profile")!

	// MARK: - Analytics

	@Test
	func `analytics factory forwards lifecycle events to the provider`() throws {
		let provider = AnalyticsProviderSpy()
		let delegate: any DeepLinkCoordinatorDelegate<TestRoute> = .analytics(provider: provider)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, willProcess: sampleURL)

		#expect(provider.trackedEvents.count == 1)
		#expect(provider.trackedEvents.first?.event == "deep_link_attempted")
	}

	// MARK: - Logging

	@Test
	func `logging factory receives every lifecycle hook without throwing`() throws {
		let delegate: any DeepLinkCoordinatorDelegate<TestRoute> = .logging()
		let coordinator = try makeCoordinator()
		let succeeded = DeepLinkResult<TestRoute>(
			originalURL: sampleURL,
			processedURL: sampleURL,
			routes: [.route1],
			executionTime: 0,
			errors: [],
			successfulRoutes: 1,
			failedRoutes: 0,
		)

		delegate.coordinator(coordinator, willProcess: sampleURL)
		delegate.coordinator(coordinator, didProcess: sampleURL, result: succeeded)
		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))
	}

	// MARK: - Notification

	#if canImport(UserNotifications) && !os(tvOS)
	@Test
	func `notification factory threads its presenter through to the delegate`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate: any DeepLinkCoordinatorDelegate<TestRoute> = .notification(
			showSuccess: false,
			showErrors: true,
			showInfo: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))

		let invocations = await presenter.waitFor(count: 1)
		let invocation = try #require(invocations.first)

		#expect(invocation.kind == .failure)
	}

	@Test
	func `notification factory defaults do not suppress error notifications`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate: any DeepLinkCoordinatorDelegate<TestRoute> = .notification(presenter: presenter)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))

		let count = await presenter.waitFor(count: 1).count
		#expect(count == 1)
	}
	#endif

	// MARK: - Composition via builder

	@Test
	func `factory-produced delegates can compose through the builder`() async throws {
		let provider = AnalyticsProviderSpy()
		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.delegate(.logging(), .analytics(provider: provider))
			.build()

		let url = try #require(URL(string: "test://example"))
		_ = await coordinator.handle(url: url)

		#expect(provider.trackedEvents.isEmpty == false)
	}

	// MARK: - Helpers

	private func makeCoordinator() throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.build()
	}
}
