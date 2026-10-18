//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct DeepLinkContextTests {
	private let customURL = URL(string: "myapp://profile/42")!
	private let webURL = URL(string: "https://example.com/profile/42")!

	// MARK: - Context

	@Test
	func `default context has an unknown source and no origin details`() {
		let context = DeepLinkContext()

		#expect(context.source == .unknown)
		#expect(context.sourceApplication == nil)
		#expect(context.sceneID == nil)
		#expect(context == .unknown)
	}

	@Test(arguments: [
		("https://example.com/a", DeepLinkContext.Source.unknown),
		("HTTP://example.com/a", .unknown),
		("myapp://a", .customScheme),
	])
	func `opened URL context never claims an unverified universal link`(string: String, expected: DeepLinkContext.Source) throws {
		let url = try #require(URL(string: string))

		let context = DeepLinkContext.openedURL(url, sourceApplication: "com.apple.mobilesafari", sceneID: "scene-1")

		#expect(context == DeepLinkContext(source: expected, sourceApplication: "com.apple.mobilesafari", sceneID: "scene-1"))
	}

	@Test
	func `request replacing its URL keeps the context`() {
		let context = DeepLinkContext(source: .notification, sceneID: "s")
		let request = DeepLinkRequest(url: customURL, context: context)

		let replaced = request.replacingURL(webURL)

		#expect(replaced == DeepLinkRequest(url: webURL, context: context))
	}

	// MARK: - Middleware Bridging

	@Test
	func `URL only middleware keeps the request context when called with a request`() async throws {
		let sut = RewritingURLMiddleware(target: webURL)
		let request = DeepLinkRequest(url: customURL, context: DeepLinkContext(source: .shortcut))

		let processed = try await sut.intercept(request)

		#expect(processed == DeepLinkRequest(url: webURL, context: DeepLinkContext(source: .shortcut)))
	}

	@Test
	func `URL only middleware stopping the chain stops the request`() async throws {
		let processed = try await StoppingMiddleware().intercept(DeepLinkRequest(url: customURL))

		#expect(processed == nil)
	}

	@Test
	func `middleware implementing neither intercept form throws instead of recursing`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("EmptyMiddleware implements neither intercept(_:) form")) {
			try await EmptyMiddleware().intercept(DeepLinkRequest(url: customURL))
		}
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("EmptyMiddleware implements neither intercept(_:) form")) {
			try await legacyIntercept(EmptyMiddleware(), customURL)
		}
	}

	@Test
	func `handler implementing neither handle form throws instead of recursing`() async {
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("EmptyHandler implements neither handle(_:) form")) {
			try await EmptyHandler().handle(.route1, context: .unknown)
		}
		await #expect(throws: DeepLinkError.missingRequiredConfiguration("EmptyHandler implements neither handle(_:) form")) {
			try await EmptyHandler().handle(.route1)
		}
	}

	@Test
	func `a URL middleware delegating to a same type instance still bridges`() async throws {
		let sut = NestingURLMiddleware(inner: NestingURLMiddleware(inner: nil))

		#expect(try await sut.intercept(DeepLinkRequest(url: customURL)) == DeepLinkRequest(url: customURL))
	}

	@Test
	func `a context handler re-entering itself through the legacy form still bridges`() async throws {
		let sut = ReentrantContextHandler()

		try await sut.handle(.route1)

		#expect(sut.received == [.unknown, .unknown])
	}

	@Test
	func `a middleware wrapping another middleware of a different type still bridges`() async throws {
		let sut = WrappingMiddleware(inner: ContextRecordingMiddleware())

		#expect(try await sut.intercept(DeepLinkRequest(url: customURL)) == DeepLinkRequest(url: customURL))
	}

	@Test
	func `request middleware called with a URL sees an unknown context`() async throws {
		let sut = ContextRecordingMiddleware()

		let processed = try await legacyIntercept(sut, customURL)

		#expect(processed == customURL)
		#expect(sut.contexts == [.unknown])
	}

	@Test
	func `middleware coordinator carries the context through legacy and request middleware`() async throws {
		let recorder = ContextRecordingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [RewritingURLMiddleware(target: webURL), recorder])
		let context = DeepLinkContext(source: .spotlight, sourceApplication: "app")

		let processed = try await sut.process(DeepLinkRequest(url: customURL, context: context))

		#expect(processed == DeepLinkRequest(url: webURL, context: context))
		#expect(recorder.contexts == [context])
		#expect(recorder.urls == [webURL])
	}

	@Test
	func `deprecated middleware coordinator URL entry points use an unknown context`() async throws {
		let recorder = ContextRecordingMiddleware()
		let anchor = CollectingMiddleware()
		let sut: any LegacyURLProcessing = DeepLinkMiddlewareCoordinator(middleware: [anchor, recorder])

		#expect(try await sut.process(customURL) == customURL)
		#expect(try await sut.process(customURL, startingAfter: anchor) == customURL)
		#expect(recorder.contexts == [.unknown, .unknown])
		#expect(anchor.interceptedURLs == [customURL])
	}

	// MARK: - Coordinator

	@Test
	func `coordinator hands the context to middleware and to the handler`() async {
		let (sut, recorder, handler) = makeCoordinator()
		let context = DeepLinkContext(source: .notification, sceneID: "scene-9")

		let result = await sut.handle(url: customURL, context: context)

		#expect(result.wasSuccessful)
		#expect(recorder.contexts == [context])
		#expect(handler.received == [ContextRecordingHandler.Call(route: .route1, context: context)])
	}

	@Test
	func `coordinator handle url defaults to an unknown context`() async {
		let (sut, recorder, handler) = makeCoordinator()

		await sut.handle(url: customURL)

		#expect(recorder.contexts == [.unknown])
		#expect(handler.received.map(\.context) == [.unknown])
	}

	@Test
	func `legacy handler still receives routes when the coordinator has a context`() async {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let sut = DeepLinkCoordinator(routing: routing, handler: handler)

		await sut.handle(url: customURL, context: DeepLinkContext(source: .intent))

		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `context aware handler called without a context sees an unknown context`() async throws {
		let handler = ContextRecordingHandler()

		try await handler.handle(.route1)

		#expect(handler.received == [ContextRecordingHandler.Call(route: .route1, context: .unknown)])
	}

	// MARK: - Security Sources

	@Test
	func `security middleware rejects a source outside allowed sources`() async {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedSources: [.universalLink], strategy: .schemeOnly)

		await #expect(throws: DeepLinkError.securityViolation("Source not allowed")) {
			try await sut.intercept(DeepLinkRequest(url: customURL, context: DeepLinkContext(source: .customScheme)))
		}
	}

	@Test
	func `security middleware admits an allowed source`() async throws {
		let sut = SecurityMiddleware.security(allowedSchemes: ["myapp"], allowedSources: [.customScheme], strategy: .schemeOnly)
		let request = DeepLinkRequest(url: customURL, context: DeepLinkContext(source: .customScheme))

		#expect(try await sut.intercept(request) == request)
	}

	@Test
	func `security middleware treats a bare URL as an unknown source`() async {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedSources: [.customScheme], strategy: .schemeOnly)

		await #expect(throws: DeepLinkError.securityViolation("Source not allowed")) {
			try await sut.intercept(url: customURL)
		}
	}

	@Test
	func `security middleware without allowed sources admits every source`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], strategy: .schemeOnly)

		for source in DeepLinkContext.Source.allCases {
			let request = DeepLinkRequest(url: customURL, context: DeepLinkContext(source: source))
			#expect(try await sut.intercept(request) == request)
		}
	}

	// MARK: - Helpers

	private func makeCoordinator() -> (DeepLinkCoordinator<TestRoute>, ContextRecordingMiddleware, ContextRecordingHandler) {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let recorder = ContextRecordingMiddleware()
		let handler = ContextRecordingHandler()
		let sut = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [recorder]),
		)
		return (sut, recorder, handler)
	}
}

// MARK: - NSUserActivity Sources

@MainActor
struct DeepLinkContextActivityTests {
	private let url = URL(string: "https://example.com/profile/42")!

	@Test
	func `browsing web activity is handled as a universal link`() async {
		let (sut, recorder) = makeSUT()

		let result = await sut.handle(activity: activity(NSUserActivityTypeBrowsingWeb), sceneID: "scene-2")

		#expect(result?.wasSuccessful == true)
		#expect(recorder.contexts == [DeepLinkContext(source: .universalLink, sceneID: "scene-2")])
	}

	@Test
	func `declared handoff activity with a URL is handled as handoff`() async {
		let (sut, recorder) = makeSUT()

		let result = await sut.handle(activity: activity("com.example.viewing"), handoffActivityTypes: ["com.example.viewing"])

		#expect(result?.wasSuccessful == true)
		#expect(recorder.contexts == [DeepLinkContext(source: .handoff)])
	}

	@Test
	func `undeclared activity type is rejected without running the pipeline`() async {
		let (sut, recorder) = makeSUT()

		let result = await sut.handle(activity: activity("com.apple.corespotlightitem"))

		#expect(result == nil)
		#expect(recorder.contexts.isEmpty)
	}

	private func activity(_ type: String) -> NSUserActivity {
		let activity = NSUserActivity(activityType: type)
		activity.webpageURL = url
		return activity
	}

	private func makeSUT() -> (DeepLinkCoordinator<TestRoute>, ContextRecordingMiddleware) {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let recorder = ContextRecordingMiddleware()
		let sut = DeepLinkCoordinator(
			routing: routing,
			handler: DeepLinkHandlerSpy<TestRoute>(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [recorder]),
		)
		return (sut, recorder)
	}
}

// MARK: - Test Doubles

private struct EmptyMiddleware: DeepLinkMiddleware {}

private struct EmptyHandler: DeepLinkHandler {
	typealias Route = TestRoute
}

private struct NestingURLMiddleware: DeepLinkMiddleware {
	let inner: (any DeepLinkMiddleware)?

	func intercept(_ url: URL) async throws -> URL? {
		guard let inner else { return url }
		return try await inner.intercept(DeepLinkRequest(url: url))?.url
	}
}

private final class ReentrantContextHandler: DeepLinkHandler {
	private let contexts = OSAllocatedUnfairLock(initialState: [DeepLinkContext.Source]())

	var received: [DeepLinkContext.Source] {
		contexts.withLock { $0 }
	}

	func handle(_ route: TestRoute, context: DeepLinkContext) async throws {
		let isFirst = contexts.withLock { sources in
			sources.append(context.source)
			return sources.count == 1
		}
		if isFirst {
			try await handle(route)
		}
	}
}

private struct WrappingMiddleware: DeepLinkMiddleware {
	let inner: any DeepLinkMiddleware

	func intercept(_ url: URL) async throws -> URL? {
		try await legacyIntercept(inner, url)
	}
}

private struct RewritingURLMiddleware: DeepLinkMiddleware {
	let target: URL

	func intercept(_: URL) async throws -> URL? {
		target
	}
}

private final class ContextRecordingMiddleware: DeepLinkMiddleware {
	private let requests = OSAllocatedUnfairLock(initialState: [DeepLinkRequest]())

	var contexts: [DeepLinkContext] {
		requests.withLock { $0.map(\.context) }
	}

	var urls: [URL] {
		requests.withLock { $0.map(\.url) }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		requests.withLock { $0.append(request) }
		return request
	}
}

private final class ContextRecordingHandler: DeepLinkHandler {
	struct Call: Equatable {
		let route: TestRoute
		let context: DeepLinkContext
	}

	private let calls = OSAllocatedUnfairLock(initialState: [Call]())

	var received: [Call] {
		calls.withLock { $0 }
	}

	func handle(_ route: TestRoute, context: DeepLinkContext) async throws {
		calls.withLock { $0.append(Call(route: route, context: context)) }
	}
}
