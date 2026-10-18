//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing
#if canImport(CoreSpotlight) && !os(tvOS)
import CoreSpotlight
#endif
#if canImport(UserNotifications) && !os(tvOS)
import UserNotifications
#endif

@MainActor
struct DeepLinkCoordinatorEntryPointsTests {
	// MARK: - Payload URL Extraction

	@Test(arguments: [
		("myapp://product/1", "myapp://product/1"),
		("https://example.com/a?b=1", "https://example.com/a?b=1"),
	])
	func `string payload values become URLs`(value: String, expected: String) {
		#expect(DeepLinkPayloadURL.url(from: ["deepLink": value], key: "deepLink") == URL(string: expected))
	}

	@Test
	func `URL payload values are used as is`() throws {
		let url = try #require(URL(string: "myapp://product/1"))

		#expect(DeepLinkPayloadURL.url(from: ["deepLink": url], key: "deepLink") == url)
	}

	@Test(arguments: ["", "not a url", "/relative/path", "product/1"])
	func `values without a scheme are rejected`(value: String) {
		#expect(DeepLinkPayloadURL.url(from: ["deepLink": value], key: "deepLink") == nil)
	}

	@Test
	func `missing key and non-string values are rejected`() {
		#expect(DeepLinkPayloadURL.url(from: ["other": "myapp://x"], key: "deepLink") == nil)
		#expect(DeepLinkPayloadURL.url(from: ["deepLink": 42], key: "deepLink") == nil)
		#expect(DeepLinkPayloadURL.url(from: nil, key: "deepLink") == nil)
	}

	// MARK: - Notifications

	#if canImport(UserNotifications) && !os(tvOS)
	@Test
	func `notification payload runs with the notification source and scene`() async throws {
		let (coordinator, middleware, handler) = makeSUT()

		let result = await coordinator.handle(
			notificationUserInfo: ["deepLink": "myapp://product/1", "aps": ["alert": "Hi"], "role": "admin"],
			sceneID: "scene-1",
		)

		#expect(result?.wasSuccessful == true)
		#expect(try middleware.interceptedRequests == [
			DeepLinkRequest(url: #require(URL(string: "myapp://product/1")), context: DeepLinkContext(source: .notification, sceneID: "scene-1")),
		])
		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `notification payload uses a custom key`() async throws {
		let (coordinator, middleware, _) = makeSUT()

		_ = await coordinator.handle(notificationUserInfo: ["link": "myapp://x"], urlKey: "link")

		#expect(try middleware.interceptedURLs == [#require(URL(string: "myapp://x"))])
	}

	@Test
	func `notification without a URL does not run the pipeline`() async {
		let (coordinator, middleware, _) = makeSUT()

		let result = await coordinator.handle(notificationUserInfo: ["aps": ["alert": "Hi"]])

		#expect(result == nil)
		#expect(middleware.interceptedRequests.isEmpty)
	}

	@Test
	func `dismissed notification does not run the pipeline`() async {
		let (coordinator, middleware, _) = makeSUT()

		let result = await coordinator.handle(
			notificationUserInfo: ["deepLink": "myapp://x"],
			actionIdentifier: UNNotificationDismissActionIdentifier,
		)

		#expect(result == nil)
		#expect(middleware.interceptedRequests.isEmpty)
	}

	@Test
	func `custom notification actions run the pipeline`() async throws {
		let (coordinator, middleware, _) = makeSUT()

		_ = await coordinator.handle(notificationUserInfo: ["deepLink": "myapp://x"], actionIdentifier: "REPLY")

		#expect(try middleware.interceptedURLs == [#require(URL(string: "myapp://x"))])
	}
	#endif

	// MARK: - Spotlight

	#if canImport(CoreSpotlight) && !os(tvOS)
	@Test
	func `searchable item identifier is the URL by default`() async throws {
		let (coordinator, middleware, _) = makeSUT()

		_ = await coordinator.handle(searchableItemIdentifier: "myapp://product/1", sceneID: "scene-2")

		#expect(try middleware.interceptedRequests == [
			DeepLinkRequest(url: #require(URL(string: "myapp://product/1")), context: DeepLinkContext(source: .spotlight, sceneID: "scene-2")),
		])
	}

	@Test
	func `searchable item identifier is mapped through the closure`() async throws {
		let (coordinator, middleware, _) = makeSUT()

		_ = await coordinator.handle(searchableItemIdentifier: "product-7") { URL(string: "myapp://product/\($0.dropFirst(8))") }

		#expect(try middleware.interceptedURLs == [#require(URL(string: "myapp://product/7"))])
	}

	@Test
	func `unmappable searchable item identifier does not run the pipeline`() async {
		let (coordinator, middleware, _) = makeSUT()

		let result = await coordinator.handle(searchableItemIdentifier: "product-7") { _ in nil }

		#expect(result == nil)
		#expect(middleware.interceptedRequests.isEmpty)
	}

	@Test
	func `searchable item activity runs with the spotlight source`() async throws {
		let (coordinator, middleware, _) = makeSUT()
		let activity = NSUserActivity(activityType: CSSearchableItemActionType)
		activity.userInfo = [CSSearchableItemActivityIdentifier: "myapp://product/1"]

		_ = await coordinator.handle(searchableItemActivity: activity)

		#expect(middleware.interceptedRequests.map(\.context.source) == [.spotlight])
		#expect(try middleware.interceptedURLs == [#require(URL(string: "myapp://product/1"))])
	}

	@Test
	func `other activity types are not handled as spotlight`() async {
		let (coordinator, middleware, _) = makeSUT()
		let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
		activity.userInfo = [CSSearchableItemActivityIdentifier: "myapp://product/1"]

		let result = await coordinator.handle(searchableItemActivity: activity)

		#expect(result == nil)
		#expect(middleware.interceptedRequests.isEmpty)
	}

	@Test
	func `searchable item activity without identifier is not handled`() async {
		let (coordinator, middleware, _) = makeSUT()

		let result = await coordinator.handle(searchableItemActivity: NSUserActivity(activityType: CSSearchableItemActionType))

		#expect(result == nil)
		#expect(middleware.interceptedRequests.isEmpty)
	}
	#endif

	// MARK: - Shortcuts

	@Test
	func `shortcut URL comes from the user info key`() {
		#expect(DeepLinkPayloadURL.shortcutURL(type: "com.app.search", userInfo: ["deepLink": "myapp://search" as NSString], key: "deepLink")
			== URL(string: "myapp://search"))
	}

	@Test
	func `shortcut type is used when it is a URL and user info has none`() {
		#expect(DeepLinkPayloadURL.shortcutURL(type: "myapp://compose", userInfo: nil, key: "deepLink") == URL(string: "myapp://compose"))
	}

	@Test
	func `shortcut without a URL is rejected`() {
		#expect(DeepLinkPayloadURL.shortcutURL(type: "com.app.compose", userInfo: nil, key: "deepLink") == nil)
	}
}

private func makeSUT() -> (DeepLinkCoordinator<TestRoute>, CollectingMiddleware, CollectingHandler<TestRoute>) {
	let middleware = CollectingMiddleware()
	let handler = CollectingHandler<TestRoute>()
	let coordinator = DeepLinkCoordinator(
		routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
		handler: handler,
		middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [middleware]),
	)
	return (coordinator, middleware, handler)
}
