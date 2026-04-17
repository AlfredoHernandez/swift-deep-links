//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@MainActor
struct DeepLinkCoordinatorDelegateFactoryTests {
	@Test
	func `Analytics delegate factory method creates delegate with correct type`() {
		let provider = DefaultAnalyticsProvider()
		let delegate: any DeepLinkCoordinatorDelegate = .analytics(provider: provider)

		#expect(delegate is DeepLinkAnalyticsDelegate)
	}

	@Test
	func `Logging delegate factory method creates delegate with correct type`() {
		let delegate: any DeepLinkCoordinatorDelegate = .logging()

		#expect(delegate is DeepLinkLoggingDelegate)
	}

	@Test
	func `Logging delegate factory method with debug enabled creates delegate`() {
		let delegate: any DeepLinkCoordinatorDelegate = .logging(enableDebugLogging: true)

		#expect(delegate is DeepLinkLoggingDelegate)
	}

	@Test
	func `Notification delegate factory method creates delegate with correct type`() {
		let delegate: any DeepLinkCoordinatorDelegate = .notification()

		#expect(delegate is DeepLinkNotificationDelegate)
	}

	@Test
	func `Notification delegate factory method with all parameters creates delegate`() {
		let delegate: any DeepLinkCoordinatorDelegate = .notification(
			showSuccess: true,
			showErrors: true,
			showInfo: true,
		)

		#expect(delegate is DeepLinkNotificationDelegate)
	}

	@Test
	func `Factory methods can be used in arrays`() {
		let provider = DefaultAnalyticsProvider()

		let delegates: [any DeepLinkCoordinatorDelegate] = [
			.analytics(provider: provider),
			.logging(enableDebugLogging: false),
			.notification(showSuccess: false, showErrors: true),
		]

		#expect(delegates.count == 3)
		#expect(delegates[0] is DeepLinkAnalyticsDelegate)
		#expect(delegates[1] is DeepLinkLoggingDelegate)
		#expect(delegates[2] is DeepLinkNotificationDelegate)
	}

	@Test
	func `Factory methods work with DeepLinkCoordinatorBuilder`() async throws {
		let provider = DefaultAnalyticsProvider()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(TestRouting())
			.handler(TestHandler())
			.middleware(.logging(), .analytics(provider: provider))
			.delegate(.logging(), .analytics(provider: provider))
			.build()

		// Verify coordinator was created successfully
		let url = try #require(URL(string: "test://example"))
		let result = await coordinator.handle(url: url)
		#expect(result.routes.count == 1)
	}

	// MARK: - Test Helpers

	enum TestRoute: DeepLinkRoute {
		case test

		var id: String {
			"test"
		}
	}

	struct TestRouting: DeepLinkRouting {
		func route(from _: URL) async throws -> [TestRoute] {
			[.test]
		}
	}

	struct TestHandler: DeepLinkHandler {
		func handle(_: TestRoute) async throws {}
	}
}
