//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("DeepLinkCoordinatorDelegate Factory Methods Tests")
@MainActor
struct DeepLinkCoordinatorDelegateFactoryTests {
	@Test("Analytics delegate factory method creates delegate with correct type")
	func analytics_factoryMethod_createsDelegateWithCorrectType() {
		let provider = DefaultAnalyticsProvider()
		let delegate: any DeepLinkCoordinatorDelegate = .analytics(provider: provider)

		#expect(delegate is DeepLinkAnalyticsDelegate)
	}

	@Test("Logging delegate factory method creates delegate with correct type")
	func logging_factoryMethod_createsDelegateWithCorrectType() {
		let delegate: any DeepLinkCoordinatorDelegate = .logging()

		#expect(delegate is DeepLinkLoggingDelegate)
	}

	@Test("Logging delegate factory method with debug enabled creates delegate")
	func logging_factoryMethodWithDebugEnabled_createsDelegate() {
		let delegate: any DeepLinkCoordinatorDelegate = .logging(enableDebugLogging: true)

		#expect(delegate is DeepLinkLoggingDelegate)
	}

	@Test("Notification delegate factory method creates delegate with correct type")
	func notification_factoryMethod_createsDelegateWithCorrectType() {
		let delegate: any DeepLinkCoordinatorDelegate = .notification()

		#expect(delegate is DeepLinkNotificationDelegate)
	}

	@Test("Notification delegate factory method with all parameters creates delegate")
	func notification_factoryMethodWithAllParameters_createsDelegate() {
		let delegate: any DeepLinkCoordinatorDelegate = .notification(
			showSuccess: true,
			showErrors: true,
			showInfo: true,
		)

		#expect(delegate is DeepLinkNotificationDelegate)
	}

	@Test("Factory methods can be used in arrays")
	func factoryMethods_canBeUsedInArrays() {
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

	@Test("Factory methods work with DeepLinkCoordinatorBuilder")
	func factoryMethods_workWithBuilder() async throws {
		let provider = DefaultAnalyticsProvider()

		let coordinator = try await DeepLinkCoordinatorBuilder<TestRoute>()
			.addingRouting(TestRouting())
			.addingHandler(TestHandler())
			.addingMiddleware(.logging())
			.addingMiddleware(.analytics(provider: provider))
			.addingDelegate(.logging())
			.addingDelegate(.analytics(provider: provider))
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
