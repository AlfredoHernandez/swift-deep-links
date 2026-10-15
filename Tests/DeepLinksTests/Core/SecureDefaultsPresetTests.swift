//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct SecureDefaultsPresetTests {
	private let routing = DeepLinkRoutingStub<TestRoute>()
	private let persistence = InMemoryRateLimitPersistence()
	private let dates = ManualDateProvider()

	init() {
		routing.routesToReturn = [.route1]
	}

	// MARK: - Security

	@Test(arguments: [
		("evil://home", SecurityViolationReason.unauthorizedScheme),
		("myapp://home/a/%2e%2e/admin", .pathTraversal),
		("https://evil.com/home", .unauthorizedHost),
		("myapp://home?q=" + String(repeating: "a", count: 2000), .inputLimitExceeded),
	])
	func `preset rejects links the hardened strategy and recommended limits reject`(
		string: String,
		reason: SecurityViolationReason,
	) async throws {
		let sut = try makeSUT()

		let result = try await sut.handle(url: #require(URL(string: string)))

		#expect(result.firstDeepLinkError?.securityViolationReason == reason)
	}

	@Test
	func `preset accepts an allowed link`() async throws {
		let sut = try makeSUT()

		let result = try await sut.handle(url: #require(URL(string: "https://example.com/home")))

		#expect(result.wasSuccessful)
	}

	@Test
	func `preset passes allowed sources to the security check`() async throws {
		let sut = try makeSUT(allowedSources: [.universalLink])
		let url = try #require(URL(string: "myapp://home"))

		let result = await sut.handle(url: url, context: DeepLinkContext(source: .customScheme))

		#expect(result.firstDeepLinkError?.securityViolationReason == .unauthorizedSource)
	}

	// MARK: - Rate Limit

	@Test
	func `preset rate limits links over the budget`() async throws {
		let sut = try makeSUT(maxRequests: 2)

		_ = try await sut.handle(url: #require(URL(string: "myapp://one")))
		_ = try await sut.handle(url: #require(URL(string: "myapp://two")))
		let third = try await sut.handle(url: #require(URL(string: "myapp://three")))

		#expect(isRateLimited(third))
	}

	@Test
	func `rejected links do not spend the rate limit budget because security runs first`() async throws {
		let sut = try makeSUT(maxRequests: 1)

		_ = try await sut.handle(url: #require(URL(string: "evil://one")))
		let allowed = try await sut.handle(url: #require(URL(string: "myapp://two")))

		#expect(allowed.wasSuccessful)
	}

	// MARK: - Replay Protection

	@Test
	func `preset drops a link replayed inside the replay window`() async throws {
		let sut = try makeSUT()
		let url = try #require(URL(string: "myapp://home"))

		_ = await sut.handle(url: url)
		let replay = await sut.handle(url: url)

		#expect(replay.wasStoppedByMiddleware)
		#expect(replay.errors.isEmpty)
	}

	@Test
	func `preset accepts the same link again after the replay window`() async throws {
		let sut = try makeSUT(replayWindow: 2)
		let url = try #require(URL(string: "myapp://home"))

		_ = await sut.handle(url: url)
		dates.advance(by: 3)
		let again = await sut.handle(url: url)

		#expect(again.wasSuccessful)
	}

	@Test
	func `replays spend the rate limit budget because rate limiting runs before replay protection`() async throws {
		let sut = try makeSUT(maxRequests: 2)
		let url = try #require(URL(string: "myapp://home"))

		_ = await sut.handle(url: url)
		_ = await sut.handle(url: url)
		let other = try await sut.handle(url: #require(URL(string: "myapp://other")))

		#expect(isRateLimited(other))
	}

	// MARK: - Placement

	@Test
	func `preset runs before middleware added earlier`() async throws {
		let collecting = CollectingMiddleware()
		let sut = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(collecting)
			.secureDefaults(allowedSchemes: ["myapp"], rateLimitPersistence: persistence, dateProvider: dates.dateProvider)
			.build()

		_ = try await sut.handle(url: #require(URL(string: "evil://home")))

		#expect(collecting.interceptedURLs.isEmpty)
	}

	@Test
	func `calling the preset again replaces the earlier configuration`() async throws {
		let sut = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.secureDefaults(allowedSchemes: ["evil"], rateLimitPersistence: persistence, dateProvider: dates.dateProvider)
			.secureDefaults(allowedSchemes: ["myapp"], rateLimitPersistence: persistence, dateProvider: dates.dateProvider)
			.build()

		let result = try await sut.handle(url: #require(URL(string: "evil://home")))

		#expect(result.firstDeepLinkError?.securityViolationReason == .unauthorizedScheme)
	}

	@Test
	func `preset cannot be combined with a custom middleware coordinator`() {
		let builder = DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middlewareCoordinator(DeepLinkMiddlewareCoordinator())
			.secureDefaults(allowedSchemes: ["myapp"])

		#expect(throws: DeepLinkError.self) {
			try builder.build()
		}
	}

	// MARK: - Missing Security Warning

	@Test
	func `build warns when no security middleware is registered`() throws {
		let log = MessageRecorder()

		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(.logging(provider: .noOp))
			.diagnosticLog(log.provider)
			.build()

		#expect(log.joined.contains("SecurityMiddleware"))
	}

	@Test
	func `build does not warn when the preset is registered`() throws {
		let log = MessageRecorder()

		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.secureDefaults(allowedSchemes: ["myapp"], rateLimitPersistence: persistence)
			.diagnosticLog(log.provider)
			.build()

		#expect(log.all.isEmpty)
	}

	@Test
	func `build does not warn when security middleware is registered directly`() throws {
		let log = MessageRecorder()

		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middleware(.logging(provider: .noOp), .security(allowedSchemes: ["myapp"]))
			.diagnosticLog(log.provider)
			.build()

		#expect(log.all.isEmpty)
	}

	@Test
	func `build does not warn for a custom middleware coordinator it cannot inspect`() throws {
		let log = MessageRecorder()

		_ = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.middlewareCoordinator(DeepLinkMiddlewareCoordinator())
			.diagnosticLog(log.provider)
			.build()

		#expect(log.all.isEmpty)
	}

	// MARK: - Helpers

	private func isRateLimited(_ result: DeepLinkResult<TestRoute>) -> Bool {
		if case .rateLimitExceeded = result.firstDeepLinkError {
			true
		} else {
			false
		}
	}

	private func makeSUT(
		allowedSources: Set<DeepLinkContext.Source>? = nil,
		maxRequests: Int = 30,
		replayWindow: TimeInterval = 2,
	) throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(routing)
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.secureDefaults(
				allowedSchemes: ["myapp", "https"],
				allowedHostsByScheme: ["https": ["example.com"]],
				allowedSources: allowedSources,
				maxRequests: maxRequests,
				rateLimitPersistence: persistence,
				replayWindow: replayWindow,
				dateProvider: dates.dateProvider,
			)
			.build()
	}
}
