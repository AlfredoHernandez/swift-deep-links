//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct SecureDefaultsTests {
	private static let secret = "abc123"
	private static let sensitiveURL = URL(string: "https://example.com/reset?token=abc123")!
	private static let sensitiveError = DeepLinkError.routeNotFound(sensitiveURL)

	// MARK: - Security Middleware

	@Test
	func `security middleware defaults to the hardened strategy`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"])
		let url = try #require(URL(string: "myapp://home/a/%2e%2e/admin"))

		await #expect(throws: DeepLinkError.securityViolation("Path traversal is not allowed")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `security factory defaults to the hardened strategy`() async throws {
		let sut = SecurityMiddleware.security(allowedSchemes: ["myapp"])
		let url = try #require(URL(string: "MyApp://Home/Profile"))

		#expect(try await sut.intercept(url: url) == URL(string: "myapp://home/Profile"))
	}

	@Test
	func `hardened accepts custom scheme links without an allowed host list`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], strategy: .hardened)
		let url = try #require(URL(string: "myapp://profile/42"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test(arguments: ["https://example.com/a", "http://example.com/a"])
	func `hardened rejects web links without an allowed host list`(string: String) async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["https", "http"], strategy: .hardened)
		let url = try #require(URL(string: string))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened still checks custom scheme hosts when hosts are listed`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["profile"], strategy: .hardened)
		let url = try #require(URL(string: "myapp://admin/1"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `standard strategy is still available`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["https"], strategy: .standard)

		#expect(try await sut.intercept(url: Self.sensitiveURL) == Self.sensitiveURL)
	}

	// MARK: - Readiness Queue

	@Test
	func `readiness queue is bounded to fifty links by default`() throws {
		let sut = DeepLinkReadinessQueue()
		let urls = try (0 ... DeepLinkReadinessQueue.defaultMaxQueueSize).map { try #require(URL(string: "myapp://item/\($0)")) }

		for url in urls {
			_ = sut.enqueue(url)
		}

		#expect(DeepLinkReadinessQueue.defaultMaxQueueSize == 50)
		#expect(sut.markReady() == Array(urls.dropFirst()))
	}

	@Test
	func `readiness queue can opt out of the bound`() throws {
		let sut = DeepLinkReadinessQueue(maxQueueSize: nil)
		let url = try #require(URL(string: "myapp://item"))

		for _ in 0 ..< 60 {
			_ = sut.enqueue(url)
		}

		#expect(sut.markReady().count == 60)
	}

	// MARK: - Log Privacy

	@Test
	func `log privacy redacts URLs, errors and free text by default`() {
		let sut = DeepLinkLogPrivacy.redacted

		#expect(sut.describe(Self.sensitiveURL) == "https://example.com/reset?token=REDACTED")
		#expect(!sut.describe(Self.sensitiveError).contains(Self.secret))
		#expect(sut.describe(TestParserError.parserError) == "TestParserError")
		#expect(sut.redactingURLs(in: "open \(Self.sensitiveURL.absoluteString) now") == "open https://example.com/reset?token=REDACTED now")
	}

	@Test
	func `unredacted log privacy keeps everything`() {
		let sut = DeepLinkLogPrivacy.unredacted

		#expect(sut.describe(Self.sensitiveURL) == Self.sensitiveURL.absoluteString)
		#expect(sut.describe(Self.sensitiveError) == Self.sensitiveError.unredactedDescription)
		#expect(sut.redactingURLs(in: Self.sensitiveURL.absoluteString) == Self.sensitiveURL.absoluteString)
	}

	// MARK: - Framework Log Sites

	@Test(arguments: [false, true])
	func `routing logs redact URLs and parser errors`(withParsers: Bool) async {
		let messages = MessageRecorder()
		let parsers: [any DeepLinkParser<TestRoute>] = withParsers ? [ThrowingParserStub(error: Self.sensitiveError)] : []
		let sut = DefaultDeepLinkRouting(parsers: parsers, log: messages.provider)

		_ = try? await sut.route(from: Self.sensitiveURL)

		#expect(!messages.all.isEmpty)
		#expect(!messages.joined.contains(Self.secret))
	}

	@Test
	func `routing logs can be unredacted`() async {
		let messages = MessageRecorder()
		let sut = DefaultDeepLinkRouting<TestRoute>(parsers: [], logPrivacy: .unredacted, log: messages.provider)

		_ = try? await sut.route(from: Self.sensitiveURL)

		#expect(messages.joined.contains(Self.secret))
	}

	@Test
	func `coordinator error logs redact errors`() async {
		let messages = MessageRecorder()
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let handler = DeepLinkHandlerSpy<TestRoute>()
		handler.shouldThrowError = true
		handler.errorRoute = .route1
		handler.errorToThrow = Self.sensitiveError
		let sut = DeepLinkCoordinator(routing: routing, handler: handler, log: messages.provider)

		await sut.handle(url: Self.sensitiveURL)
		await DeepLinkCoordinator(routing: ThrowingRouting(error: Self.sensitiveError), handler: handler, log: messages.provider)
			.handle(url: Self.sensitiveURL)

		#expect(messages.all.count >= 2)
		#expect(!messages.joined.contains(Self.secret))
	}

	@Test
	func `coordinator error logs can be unredacted`() async {
		let messages = MessageRecorder()
		let sut = DeepLinkCoordinator(
			routing: ThrowingRouting<TestRoute>(error: Self.sensitiveError),
			handler: DeepLinkHandlerSpy<TestRoute>(),
			logPrivacy: .unredacted,
			log: messages.provider,
		)

		await sut.handle(url: Self.sensitiveURL)

		#expect(messages.joined.contains(Self.secret))
	}

	@Test
	func `readiness middleware log redacts the queued URL`() async throws {
		let messages = MessageRecorder()
		let sut = ReadinessMiddleware(queue: DeepLinkReadinessQueue(), log: messages.provider)

		_ = try await sut.intercept(url: Self.sensitiveURL)

		#expect(!messages.all.isEmpty)
		#expect(!messages.joined.contains(Self.secret))
	}

	@Test
	func `default analytics provider redacts URLs and sensitive parameters`() {
		let messages = MessageRecorder()
		let sut = DefaultAnalyticsProvider(log: messages.provider)

		sut.track("deep_link_opened", parameters: ["url": Self.sensitiveURL.absoluteString, "token": Self.secret, "lang": "en"])

		#expect(messages.joined.contains("lang: en"))
		#expect(!messages.joined.contains(Self.secret))
	}

	@Test
	func `default analytics provider can be unredacted`() {
		let messages = MessageRecorder()
		let sut = DefaultAnalyticsProvider(privacy: .unredacted, log: messages.provider)

		sut.track("deep_link_opened", parameters: ["token": Self.secret])

		#expect(messages.joined.contains(Self.secret))
	}

	@Test
	func `console provider redacts URLs in messages by default`() {
		let lines = MessageRecorder()
		let sut = LoggingProvider.console(privacy: .redacted) { lines.provider.log(level: .info, $0) }

		sut.log(level: .info, "Deep link: \(Self.sensitiveURL.absoluteString)")

		#expect(lines.all == ["[info] Deep link: https://example.com/reset?token=REDACTED"])
	}

	@Test
	func `unredacted console provider prints the message unchanged`() {
		let lines = MessageRecorder()
		let sut = LoggingProvider.console(privacy: .unredacted) { lines.provider.log(level: .info, $0) }

		sut.log(level: .error, "Deep link: \(Self.sensitiveURL.absoluteString)")

		#expect(lines.all == ["[error] Deep link: \(Self.sensitiveURL.absoluteString)"])
	}
}

// MARK: - Delegates

@MainActor
struct SecureDelegateDefaultsTests {
	private static let secret = "abc123"
	private static let sensitiveURL = URL(string: "https://example.com/reset?token=abc123")!
	private static let sensitiveError = DeepLinkError.routeNotFound(sensitiveURL)

	@Test
	func `logging delegate redacts every message by default`() {
		let messages = MessageRecorder()
		let sut = DeepLinkLoggingDelegate<TestRoute>(enableDebugLogging: true, log: messages.provider)
		let coordinator = makeCoordinator()

		sut.coordinator(coordinator, willProcess: Self.sensitiveURL)
		sut.coordinator(coordinator, didProcess: Self.sensitiveURL, result: failedResult())
		sut.coordinator(coordinator, didFailProcessing: Self.sensitiveURL, error: Self.sensitiveError)

		#expect(messages.all.count >= 5)
		#expect(!messages.joined.contains(Self.secret))
	}

	@Test
	func `logging delegate can be unredacted`() {
		let messages = MessageRecorder()
		let sut = DeepLinkLoggingDelegate<TestRoute>(privacy: .unredacted, log: messages.provider)

		sut.coordinator(makeCoordinator(), willProcess: Self.sensitiveURL)

		#expect(messages.joined.contains(Self.secret))
	}

	@Test
	func `analytics delegate redacts URLs and error descriptions by default`() {
		let provider = CollectingAnalyticsProvider()
		let sut = DeepLinkAnalyticsDelegate<TestRoute>(analyticsProvider: provider)
		let coordinator = makeCoordinator()

		sut.coordinator(coordinator, willProcess: Self.sensitiveURL)
		sut.coordinator(coordinator, didProcess: Self.sensitiveURL, result: failedResult())
		sut.coordinator(coordinator, didFailProcessing: Self.sensitiveURL, error: Self.sensitiveError)

		let tracked = provider.trackedEvents.map { "\($0.parameters)" }.joined()
		#expect(provider.trackedEvents.count == 3)
		#expect(!tracked.contains(Self.secret))
		#expect(tracked.contains("REDACTED"))
	}

	@Test
	func `analytics delegate can be unredacted`() {
		let provider = CollectingAnalyticsProvider()
		let sut = DeepLinkAnalyticsDelegate<TestRoute>(analyticsProvider: provider, privacy: .unredacted)

		sut.coordinator(makeCoordinator(), didFailProcessing: Self.sensitiveURL, error: Self.sensitiveError)

		#expect("\(provider.trackedEvents.map(\.parameters))".contains(Self.secret))
	}

	private func failedResult() -> DeepLinkResult<TestRoute> {
		DeepLinkResult<TestRoute>(
			originalURL: Self.sensitiveURL,
			processedURL: nil,
			routes: [],
			executionTime: 0,
			errors: [Self.sensitiveError],
			successfulRoutes: 0,
			failedRoutes: 0,
		)
	}

	private func makeCoordinator() -> DeepLinkCoordinator<TestRoute> {
		DeepLinkCoordinator(routing: DeepLinkRoutingStub<TestRoute>(), handler: DeepLinkHandlerSpy<TestRoute>())
	}
}

private struct ThrowingRouting<Route: DeepLinkRoute>: DeepLinkRouting {
	let error: DeepLinkError

	func route(from _: URL) async throws -> [Route] {
		throw error
	}
}
