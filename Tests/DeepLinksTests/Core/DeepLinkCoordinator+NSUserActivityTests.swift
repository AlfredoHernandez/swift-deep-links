//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

@MainActor
struct DeepLinkCoordinatorNSUserActivityTests {
	@Test
	func `handle activity delivers result when webpageURL is set`() async throws {
		let (coordinator, routing, handler) = makeSUT()
		let url = try #require(URL(string: "https://example.com/profile?userID=42"))
		routing.routesToReturn = [.route1]
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.webpageURL = url

		let result = await coordinator.handle(activity: activity)

		#expect(result?.wasSuccessful == true)
		#expect(result?.originalURL == url)
		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `handle activity ignores referrerURL and delivers nil when webpageURL is absent`() async throws {
		let (coordinator, _, handler) = makeSUT()
		let referrer = try #require(URL(string: "https://example.com/from-email"))
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.referrerURL = referrer

		let result = await coordinator.handle(activity: activity)

		#expect(result == nil)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `handle activity delivers nil when no URL is present`() async {
		let (coordinator, _, handler) = makeSUT()
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)

		let result = await coordinator.handle(activity: activity)

		#expect(result == nil)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `handle activity surfaces routing error as unsuccessful result`() async throws {
		let (coordinator, routing, handler) = makeSUT()
		let url = try #require(URL(string: "https://example.com/bad"))
		routing.shouldThrowError = true
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.webpageURL = url

		let result = await coordinator.handle(activity: activity)

		#expect(result?.wasSuccessful == false)
		#expect(result?.errors.count == 1)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `handle activity surfaces handler error as unsuccessful result`() async throws {
		let (coordinator, routing, handler) = makeSUT()
		let url = try #require(URL(string: "https://example.com/profile"))
		routing.routesToReturn = [.route1]
		handler.shouldThrowError = true
		handler.errorRoute = .route1
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.webpageURL = url

		let result = await coordinator.handle(activity: activity)

		#expect(result?.wasSuccessful == false)
		#expect(result?.failedRoutes == 1)
		#expect(result?.errors.count == 1)
	}

	@Test
	func `handle activity returns stopped result when middleware halts processing`() async throws {
		let routing = DeepLinkRoutingStub<TestRoute>()
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: middlewareCoordinator,
		)
		let url = try #require(URL(string: "https://example.com/gated"))
		await middlewareCoordinator.add(StoppingMiddleware())
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.webpageURL = url

		let result = await coordinator.handle(activity: activity)

		#expect(result?.wasStoppedByMiddleware == true)
		#expect(result?.wasSuccessful == false)
		#expect(handler.handledRoutes.isEmpty)
	}

	@Test
	func `handle activity can be discarded at call site`() async throws {
		let (coordinator, routing, _) = makeSUT()
		let url = try #require(URL(string: "https://example.com/discarded"))
		routing.routesToReturn = [.route1]
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.webpageURL = url

		// `@discardableResult` lets callers ignore the return value without a warning.
		await coordinator.handle(activity: activity)
	}

	// MARK: - Helpers

	private typealias SUT = (
		coordinator: DeepLinkCoordinator<TestRoute>,
		routing: DeepLinkRoutingStub<TestRoute>,
		handler: DeepLinkHandlerSpy<TestRoute>,
	)

	private func makeSUT() -> SUT {
		let routing = DeepLinkRoutingStub<TestRoute>()
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routing, handler: handler)
		return (coordinator, routing, handler)
	}
}
