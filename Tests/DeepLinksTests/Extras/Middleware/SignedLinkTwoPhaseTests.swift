//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import os
import Testing

struct SignedLinkTwoPhaseTests {
	@Test
	func `a link that completes spends its nonce`() async {
		let sut = Pipeline()

		#expect(await sut.open(sut.link).wasSuccessful)

		let replay = await sut.open(sut.link)
		#expect(replay.firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a link rejected by a later middleware can be retried`() async {
		let gate = ToggleMiddleware(allows: false)
		let sut = Pipeline(after: [gate])

		#expect(await !sut.open(sut.link).wasSuccessful)
		gate.allows = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a link stopped by a later middleware can be retried`() async {
		let gate = ToggleMiddleware(allows: false, stops: true)
		let sut = Pipeline(after: [gate])

		#expect(await sut.open(sut.link).wasStoppedByMiddleware)
		gate.allows = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a declined confirmation leaves the link usable`() async throws {
		let confirmation = CollectingConfirmation(approves: false)
		let sut = Pipeline(after: [ConfirmationMiddleware(provider: confirmation)])

		#expect(try await sut.open(sut.link).firstDeepLinkError == .confirmationDenied(#require(URL(string: "https://example.com/reset"))))
		confirmation.approves = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a link the parsers reject can be retried`() async {
		let parser = ToggleParser(succeeds: false)
		let sut = Pipeline(parser: parser)

		#expect(await !sut.open(sut.link).wasSuccessful)
		parser.succeeds = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a link whose handler ran and failed spends its nonce, since the handler may have acted`() async {
		let handler = ToggleHandler(succeeds: false)
		let sut = Pipeline(handler: handler)

		#expect(await !sut.open(sut.link).wasSuccessful)
		handler.succeeds = true

		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a route confirmation the user denies releases the nonce, like the confirmation middleware`() async throws {
		let routedURL = try #require(URL(string: "https://example.com/reset"))
		let answer = ConfirmationAnswer()
		let sut = Pipeline(handler: CollectingHandler<TestRoute>().confirming(.all) { _, _ in answer.approves })

		#expect(await sut.open(sut.link).firstDeepLinkError == .confirmationDenied(routedURL))
		answer.approves = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a route guard declining a signed-out user releases the nonce for the resumed link`() async throws {
		let routedURL = try #require(URL(string: "https://example.com/reset"))
		let auth = ToggleAuthentication()
		let sut = Pipeline(handler: CollectingHandler<TestRoute>().requiringAuthentication(for: .all, provider: auth))

		#expect(await sut.open(sut.link).firstDeepLinkError == .unauthorizedAccess(routedURL))
		auth.isSignedIn = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a denial after another route ran still spends the nonce`() async {
		let handler = CollectingHandler<TestRoute>().confirming(.routes { $0 == .route2 }) { _, _ in false }
		let sut = Pipeline(parser: ImmediateParser(routes: [TestRoute.route1, .route2]), handler: handler)

		#expect(await sut.open(sut.link).successfulRoutes == 1)
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a handler throwing a denial error itself still spends the nonce`() async throws {
		let blank = try #require(URL(string: "about:blank"))
		let sut = Pipeline(handler: ThrowingRouteHandler(error: DeepLinkError.confirmationDenied(blank)))

		#expect(await !sut.open(sut.link).wasSuccessful)
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a link with one failing route among several spends its nonce`() async {
		let handler = FailingOnRoute2Handler()
		let sut = Pipeline(parser: ImmediateParser(routes: [TestRoute.route1, .route2]), handler: handler)

		let first = await sut.open(sut.link)

		#expect(first.successfulRoutes == 1)
		#expect(first.failedRoutes == 1)
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a protected link resumed after sign-in uses its nonce once`() async {
		let auth = ToggleAuthentication()
		let pending = InMemoryPendingLinkStore()
		let sut = Pipeline(after: [AuthenticationMiddleware(authProvider: auth, protectedHosts: ["example.com"], pendingLinks: pending)])

		#expect(await !sut.open(sut.link).wasSuccessful)
		auth.isSignedIn = true
		let resumed = await sut.coordinator.resumePendingLinks(from: pending)

		#expect(resumed.map(\.wasSuccessful) == [true])
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a link queued for readiness holds its nonce and spends it when it drains`() async {
		let queue = DeepLinkReadinessQueue()
		let sut = Pipeline(after: [ReadinessMiddleware(queue: queue)])

		#expect(await sut.open(sut.link).wasStoppedByMiddleware)
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))

		#expect(await sut.coordinator.markReadyAndDrain(queue: queue).map(\.wasSuccessful) == [true])
		sut.clock.advance(by: InMemoryNonceStore.defaultReservationTTL + 1)
		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a queued link that fails after draining can be retried`() async {
		let queue = DeepLinkReadinessQueue()
		let gate = ToggleMiddleware(allows: false)
		let sut = Pipeline(after: [ReadinessMiddleware(queue: queue), gate])
		_ = await sut.open(sut.link)

		#expect(await sut.coordinator.markReadyAndDrain(queue: queue).map(\.wasSuccessful) == [false])
		gate.allows = true

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test(.timeLimit(.minutes(1)))
	func `an evicted queued link releases its nonce`() async throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: 1)
		let store = SignalingNonceStore()
		let sut = Pipeline(after: [ReadinessMiddleware(queue: queue)], nonceStore: store.wrapping)
		var releases = store.releases.makeAsyncIterator()
		_ = await sut.open(sut.link)

		let other = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/other")), expiresAt: sut.clock.now + 600, nonce: "n-2")
		_ = await sut.open(other)
		#expect(await releases.next() == "n-1")
		_ = queue.markReady()

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test(.timeLimit(.minutes(1)))
	func `resetting the readiness queue releases queued nonces`() async {
		let queue = DeepLinkReadinessQueue()
		let store = SignalingNonceStore()
		let sut = Pipeline(after: [ReadinessMiddleware(queue: queue)], nonceStore: store.wrapping)
		var releases = store.releases.makeAsyncIterator()
		_ = await sut.open(sut.link)

		queue.reset()
		#expect(await releases.next() == "n-1")
		_ = queue.markReady()

		#expect(await sut.open(sut.link).wasSuccessful)
	}

	@Test
	func `a signed link processed inside a handler does not disturb the outer link's nonce`() async throws {
		let clock = ManualDateProvider()
		let signed = SignedLinkMiddleware(
			keys: SigningKeyring(key: key),
			nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider),
			dateProvider: clock.dateProvider,
		)
		let chain = DeepLinkMiddlewareCoordinator(middleware: [signed])
		let inner = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/inner")), expiresAt: clock.now + 600, nonce: "inner")
		let outer = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/outer")), expiresAt: clock.now + 600, nonce: "outer")
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: NestedProcessingHandler(chain: chain, link: inner),
			middlewareCoordinator: chain,
		)

		#expect(await coordinator.handle(url: outer).wasSuccessful)
		clock.advance(by: InMemoryNonceStore.defaultReservationTTL + 1)

		#expect(await coordinator.handle(url: outer).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.reusedNonceReason)) {
			try await chain.process(DeepLinkRequest(url: inner))
		}
	}

	@Test(.timeLimit(.minutes(1)))
	func `a link still waiting for confirmation keeps its nonce past the reservation time to live`() async throws {
		let clock = ManualDateProvider()
		let prompts = AsyncStream<CheckedContinuation<Bool, Never>>.makeStream()
		let promptCount = OSAllocatedUnfairLock(initialState: 0)
		let handler = CollectingHandler<TestRoute>().confirming(.all) { _, _ in
			let isFirst = promptCount.withLock { count in
				count += 1
				return count == 1
			}
			guard isFirst else { return false }
			return await withCheckedContinuation { prompts.continuation.yield($0) }
		}
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(
					keys: SigningKeyring(key: key),
					nonceStore: InMemoryNonceStore(reservationTTL: 30, dateProvider: clock.dateProvider),
					dateProvider: clock.dateProvider,
				),
			]),
		)
		let link = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/pay")), expiresAt: clock.now + 600, nonce: "n-1")
		var pending = prompts.stream.makeAsyncIterator()

		let first = Task { await coordinator.handle(url: link) }
		let prompt = try #require(await pending.next())
		clock.advance(by: 31)

		let second = await coordinator.handle(url: link)
		prompt.resume(returning: true)

		#expect(second.firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
		#expect(await first.value.wasSuccessful)
		#expect(await coordinator.handle(url: link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `a signed link queued, drained while signed out and resumed after sign-in still verifies`() async {
		let queue = DeepLinkReadinessQueue()
		let auth = ToggleAuthentication()
		let pending = InMemoryPendingLinkStore()
		let sut = Pipeline(after: [
			ReadinessMiddleware(queue: queue),
			AuthenticationMiddleware(authProvider: auth, protectedHosts: ["example.com"], pendingLinks: pending),
		])
		_ = await sut.open(sut.link)

		#expect(await sut.coordinator.markReadyAndDrain(queue: queue).map(\.wasSuccessful) == [false])
		auth.isSignedIn = true

		#expect(await sut.coordinator.resumePendingLinks(from: pending).map(\.wasSuccessful) == [true])
	}

	@Test
	func `a consume-only custom store spends the nonce at reservation, so a rejected link cannot be retried`() async {
		let gate = ToggleMiddleware(allows: false)
		let sut = Pipeline(after: [gate], nonceStore: { _ in ConsumeOnlyStore() })

		#expect(await !sut.open(sut.link).wasSuccessful)
		gate.allows = true

		#expect(await sut.open(sut.link).firstDeepLinkError == .securityViolation(SignedLinkMiddleware.reusedNonceReason))
	}

	@Test
	func `concurrent deliveries through the coordinator admit exactly one`() async {
		let sut = Pipeline()
		let link = sut.link

		let successes = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 20 {
				group.addTask { await sut.open(link).wasSuccessful }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(successes == 1)
	}
}

// MARK: - Helpers

private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

private struct Pipeline: Sendable {
	let clock = ManualDateProvider()
	let coordinator: DeepLinkCoordinator<TestRoute>
	let link: URL

	init(
		after: [any DeepLinkMiddleware] = [],
		parser: any DeepLinkParser<TestRoute> = ImmediateParser(routes: [TestRoute.route1]),
		handler: any DeepLinkHandler<TestRoute> = CollectingHandler<TestRoute>(),
		nonceStore: ((@escaping @Sendable () -> Date) -> any NonceStore)? = nil,
	) {
		let signed = SignedLinkMiddleware(
			keys: SigningKeyring(key: key),
			nonceStore: nonceStore?(clock.dateProvider) ?? InMemoryNonceStore(dateProvider: clock.dateProvider),
			dateProvider: clock.dateProvider,
		)
		coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [parser]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [signed] + after),
		)
		link = try! SignedLinkBuilder(key: key).sign(URL(string: "https://example.com/reset")!, expiresAt: clock.now + 600, nonce: "n-1")
	}

	func open(_ url: URL) async -> DeepLinkResult<TestRoute> {
		await coordinator.handle(url: url, context: DeepLinkContext(source: .universalLink))
	}
}

private final class ConfirmationAnswer: Sendable {
	private let state = OSAllocatedUnfairLock(initialState: false)

	var approves: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}
}

private struct ThrowingRouteHandler: DeepLinkHandler {
	let error: any Error & Sendable

	func handle(_: TestRoute) async throws {
		throw error
	}
}

private final class ToggleMiddleware: DeepLinkMiddleware {
	private let state: OSAllocatedUnfairLock<Bool>
	private let stops: Bool

	init(allows: Bool, stops: Bool = false) {
		state = OSAllocatedUnfairLock(initialState: allows)
		self.stops = stops
	}

	var allows: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		if allows {
			return request
		}
		if stops {
			return nil
		}
		throw DeepLinkError.unauthorizedAccess(request.url)
	}
}

private final class ToggleParser: DeepLinkParser {
	private let state: OSAllocatedUnfairLock<Bool>

	init(succeeds: Bool) {
		state = OSAllocatedUnfairLock(initialState: succeeds)
	}

	var succeeds: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func parse(from url: URL) async throws -> [TestRoute] {
		guard succeeds else { throw DeepLinkError.routeNotFound(url) }
		return [.route1]
	}
}

private final class ToggleHandler: DeepLinkHandler {
	private let state: OSAllocatedUnfairLock<Bool>

	init(succeeds: Bool) {
		state = OSAllocatedUnfairLock(initialState: succeeds)
	}

	var succeeds: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		guard succeeds else { throw DeepLinkError.handlerError(message: "not yet", underlyingError: nil) }
	}
}

private final class ToggleAuthentication: AuthenticationProvider {
	private let state = OSAllocatedUnfairLock(initialState: false)

	var isSignedIn: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func isAuthenticated() -> Bool {
		isSignedIn
	}
}

private struct FailingOnRoute2Handler: DeepLinkHandler {
	func handle(_ route: TestRoute, context _: DeepLinkContext) async throws {
		if route == .route2 {
			throw DeepLinkError.handlerError(message: "route 2", underlyingError: nil)
		}
	}
}

/// Processes `link` through `chain` the first time it handles a route.
private final class NestedProcessingHandler: DeepLinkHandler {
	private let chain: DeepLinkMiddlewareCoordinator
	private let link: URL
	private let hasNested = OSAllocatedUnfairLock(initialState: false)

	init(chain: DeepLinkMiddlewareCoordinator, link: URL) {
		self.chain = chain
		self.link = link
	}

	func handle(_: TestRoute, context _: DeepLinkContext) async throws {
		guard !hasNested.withLock({ defer { $0 = true }; return $0 }) else { return }
		_ = try await chain.process(DeepLinkRequest(url: link))
	}
}

/// An in-memory store that announces every released nonce.
private final class SignalingNonceStore: Sendable {
	private let releaseEvents = AsyncStream<String>.makeStream()
	private let inner = OSAllocatedUnfairLock<InMemoryNonceStore?>(initialState: nil)

	var releases: AsyncStream<String> {
		releaseEvents.stream
	}

	var wrapping: (@escaping @Sendable () -> Date) -> any NonceStore {
		{ [self] dateProvider in
			let store = InMemoryNonceStore(dateProvider: dateProvider)
			inner.withLock { $0 = store }
			return Forwarding(store: store, onRelease: { [releaseEvents] in releaseEvents.continuation.yield($0) })
		}
	}

	private struct Forwarding: NonceStore {
		let store: InMemoryNonceStore
		let onRelease: @Sendable (String) -> Void

		func consume(_ nonce: String, expiresAt: Date) async -> Bool {
			await store.consume(nonce, expiresAt: expiresAt)
		}

		func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
			await store.reserve(nonce, expiresAt: expiresAt)
		}

		func commit(_ reservation: NonceReservation) async {
			await store.commit(reservation)
		}

		func release(_ reservation: NonceReservation) async {
			await store.release(reservation)
			onRelease(reservation.nonce)
		}
	}
}

/// A 1.x-style store implementing only `consume`.
private final class ConsumeOnlyStore: NonceStore {
	private let seen = OSAllocatedUnfairLock<Set<String>>(initialState: [])

	func consume(_ nonce: String, expiresAt _: Date) async -> Bool {
		seen.withLock { $0.insert(nonce).inserted }
	}
}

#endif
