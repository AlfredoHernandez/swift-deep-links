//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import Testing

struct SignedLinkNestedReadinessTests {
	enum StoreKind: CaseIterable {
		case inMemory
		case userDefaults
	}

	private let cleanup = UserDefaultsSuiteCleanup()

	@Test(arguments: StoreKind.allCases)
	func `a link drained through two readiness gates spends its nonce`(kind: StoreKind) async throws {
		let clock = ManualDateProvider()
		let store = try makeStore(kind, clock: clock)
		let firstQueue = DeepLinkReadinessQueue()
		let secondQueue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), nonceStore: store, dateProvider: clock.dateProvider),
				ReadinessMiddleware(queue: firstQueue),
				ReadinessMiddleware(queue: secondQueue),
			]),
		)
		let link = try SignedLinkBuilder(key: key)
			.sign(#require(URL(string: "https://example.com/reset")), expiresAt: clock.now + 600, nonce: "n-1")

		_ = await coordinator.handle(url: link, context: DeepLinkContext(source: .universalLink))
		_ = await coordinator.markReadyAndDrain(queue: firstQueue)
		let drained = await coordinator.markReadyAndDrain(queue: secondQueue)
		clock.advance(by: InMemoryNonceStore.defaultReservationTTL + 1)

		#expect(drained.map(\.wasSuccessful) == [true])
		#expect(handler.handledRoutes == [.route1])
		#expect(await store.reserve("n-1", expiresAt: clock.now + 600) == nil)
	}

	@Test(.timeLimit(.minutes(1)))
	func `a link reset at the second readiness gate releases the nonce reserved before the first`() async throws {
		let clock = ManualDateProvider()
		let store = ReleaseSignalingStore(wrapping: InMemoryNonceStore(dateProvider: clock.dateProvider))
		var releases = store.releases.makeAsyncIterator()
		let firstQueue = DeepLinkReadinessQueue()
		let secondQueue = DeepLinkReadinessQueue()
		let coordinator = DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: CollectingHandler<TestRoute>(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), nonceStore: store, dateProvider: clock.dateProvider),
				ReadinessMiddleware(queue: firstQueue),
				ReadinessMiddleware(queue: secondQueue),
			]),
		)
		let link = try SignedLinkBuilder(key: key)
			.sign(#require(URL(string: "https://example.com/reset")), expiresAt: clock.now + 600, nonce: "n-1")
		_ = await coordinator.handle(url: link, context: DeepLinkContext(source: .universalLink))
		_ = await coordinator.markReadyAndDrain(queue: firstQueue)

		secondQueue.reset()

		#expect(await releases.next() == "n-1")
		#expect(await store.reserve("n-1", expiresAt: clock.now + 600) != nil)
	}

	private func makeStore(_ kind: StoreKind, clock: ManualDateProvider) throws -> any NonceStore {
		switch kind {
		case .inMemory:
			return InMemoryNonceStore(dateProvider: clock.dateProvider)

		case .userDefaults:
			let suiteName = "nested-readiness.\(UUID().uuidString)"
			cleanup.track(suiteName)
			return try UserDefaultsNonceStore(userDefaults: #require(UserDefaults(suiteName: suiteName)), dateProvider: clock.dateProvider)
		}
	}
}

private let key = SymmetricKey(data: Data(repeating: 3, count: 32))

private struct ReleaseSignalingStore: NonceStore {
	private let store: InMemoryNonceStore
	private let events = AsyncStream<String>.makeStream()

	init(wrapping store: InMemoryNonceStore) {
		self.store = store
	}

	var releases: AsyncStream<String> {
		events.stream
	}

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
		events.continuation.yield(reservation.nonce)
	}
}

#endif
