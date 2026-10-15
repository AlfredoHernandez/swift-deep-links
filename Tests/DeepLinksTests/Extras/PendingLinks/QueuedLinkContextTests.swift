//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct QueuedLinkContextTests {
	private let cleanup = UserDefaultsSuiteCleanup()
	private let context = DeepLinkContext(source: .notification, sourceApplication: "com.example.mail", sceneID: "scene-A")

	// MARK: - Readiness

	@Test
	func `a drained link reaches the handler with the context it arrived with`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [ReadinessMiddleware(queue: queue)])
		_ = await coordinator.handle(url: url("myapp://a"), context: context)

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledContexts == [context])
	}

	@Test
	func `the readiness queue keeps requests and still answers in URLs`() {
		let queue = DeepLinkReadinessQueue()

		#expect(queue.enqueue(DeepLinkRequest(url: url("myapp://a"), context: context)) == nil)
		#expect(queue.enqueue(url("myapp://b")) == nil)

		#expect(queue.pendingRequests == [
			DeepLinkRequest(url: url("myapp://a"), context: context),
			DeepLinkRequest(url: url("myapp://b")),
		])
		#expect(queue.pendingURLs == [url("myapp://a"), url("myapp://b")])
		#expect(queue.markReadyReturningRequests().map(\.context) == [context, .unknown])
		#expect(queue.enqueue(DeepLinkRequest(url: url("myapp://c"), context: context))?.context == context)
	}

	@Test
	func `a URL-only readiness queue still drains, with an unknown context`() async {
		let queue = URLOnlyReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(handler: handler, middleware: [ReadinessMiddleware(queue: queue)])
		_ = await coordinator.handle(url: url("myapp://a"), context: context)

		_ = await coordinator.markReadyAndDrain(queue: queue)

		#expect(handler.handledRoutes == [.route1])
		#expect(handler.handledContexts == [.unknown])
	}

	// MARK: - Pending Links

	@Test(arguments: [false, true])
	func `a resumed link reaches the handler with the context it arrived with`(persisted: Bool) async throws {
		let store: any PendingLinkStore = persisted ? try UserDefaultsPendingLinkStore(userDefaults: makeDefaults(), key: "pending") : InMemoryPendingLinkStore()
		let auth = SwitchableAuthentication()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = makeCoordinator(
			handler: handler,
			middleware: [AuthenticationMiddleware(authProvider: auth, protectedHosts: ["account"], pendingLinks: store)],
		)
		_ = await coordinator.handle(url: url("myapp://account"), context: context)

		auth.isSignedIn = true
		_ = await coordinator.resumePendingLinks(from: store)

		var resumed = context
		resumed.isResumedPendingLink = true
		#expect(handler.handledContexts == [resumed])
	}

	@Test
	func `the UserDefaults store keeps the context across relaunches`() async throws {
		let suiteName = makeSuiteName()
		try await UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "pending")
			.save(DeepLinkRequest(url: url("myapp://a"), context: context))

		let relaunched = try UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "pending")

		#expect(await relaunched.takeAllRequests() == [DeepLinkRequest(url: url("myapp://a"), context: context)])
	}

	@Test
	func `the UserDefaults store never persists a verified signature`() async throws {
		let suiteName = makeSuiteName()
		var verified = context
		verified.signatureVerifiedURL = url("myapp://a")
		try await UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "pending")
			.save(DeepLinkRequest(url: url("myapp://a"), context: verified))

		let restored = try await UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "pending").takeAllRequests()

		#expect(restored.map(\.context) == [context])
	}

	@Test
	func `stored links from 1.x or with an unknown source load with an unknown source`() async throws {
		let suiteName = makeSuiteName()
		let legacy = #"[{"url":"myapp:\/\/old","savedAt":1700000000}]"#
		let future = #"[{"url":"myapp:\/\/new","savedAt":1700000000,"context":{"version":1,"source":"carrierPigeon","sceneID":"scene-B"}}]"#
		let clock = ManualDateProvider()

		UserDefaults(suiteName: suiteName)?.set(Data(legacy.utf8), forKey: "legacy")
		UserDefaults(suiteName: suiteName)?.set(Data(future.utf8), forKey: "future")

		let old = try await UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "legacy", dateProvider: clock.dateProvider)
			.takeAllRequests()
		let new = try await UserDefaultsPendingLinkStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), key: "future", dateProvider: clock.dateProvider)
			.takeAllRequests()

		#expect(old == [DeepLinkRequest(url: url("myapp://old"))])
		#expect(new == [DeepLinkRequest(url: url("myapp://new"), context: DeepLinkContext(sceneID: "scene-B"))])
	}

	@Test
	func `a URL-only pending store still resumes, with an unknown context`() async {
		let store = URLOnlyPendingLinkStore()
		await store.save(DeepLinkRequest(url: url("myapp://a"), context: context))

		#expect(await store.takeAllRequests() == [DeepLinkRequest(url: url("myapp://a"))])
	}

	// MARK: - Helpers

	private func makeSuiteName() -> String {
		let suiteName = "pending.context.\(UUID().uuidString)"
		cleanup.track(suiteName)
		return suiteName
	}

	private func makeDefaults() throws -> UserDefaults {
		try #require(UserDefaults(suiteName: makeSuiteName()))
	}
}

private func makeCoordinator(handler: CollectingHandler<TestRoute>, middleware: [any DeepLinkMiddleware]) -> DeepLinkCoordinator<TestRoute> {
	DeepLinkCoordinator(
		routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
		handler: handler,
		middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
	)
}

private func url(_ string: String) -> URL {
	URL(string: string)!
}

private final class SwitchableAuthentication: AuthenticationProvider {
	private let state = OSAllocatedUnfairLock(initialState: false)

	var isSignedIn: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func isAuthenticated() -> Bool {
		isSignedIn
	}
}

/// A 1.x-style queue implementing only the URL requirements.
private final class URLOnlyReadinessQueue: ReadinessQueue {
	private let state = OSAllocatedUnfairLock<(ready: Bool, urls: [URL])>(initialState: (false, []))

	var isReady: Bool {
		state.withLock { $0.ready }
	}

	var pendingCount: Int {
		state.withLock { $0.urls.count }
	}

	var pendingURLs: [URL] {
		state.withLock { $0.urls }
	}

	func enqueue(_ url: URL) -> URL? {
		state.withLock { state in
			guard !state.ready else { return url }
			state.urls.append(url)
			return nil
		}
	}

	func markReady() -> [URL] {
		state.withLock { state in
			state.ready = true
			defer { state.urls = [] }
			return state.urls
		}
	}

	func reset() {
		state.withLock { $0 = (false, []) }
	}
}

/// A 1.x-style pending store implementing only the URL requirements.
private actor URLOnlyPendingLinkStore: PendingLinkStore {
	private var urls: [URL] = []

	func save(_ url: URL) async {
		urls.append(url)
	}

	func takeAll() async -> [URL] {
		defer { urls = [] }
		return urls
	}

	func removeAll() async {
		urls = []
	}
}
