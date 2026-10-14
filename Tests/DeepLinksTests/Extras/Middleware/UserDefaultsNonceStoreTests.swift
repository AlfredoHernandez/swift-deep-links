//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct UserDefaultsNonceStoreTests {
	private let cleanup = UserDefaultsSuiteCleanup()
	private let clock = ManualDateProvider()

	@Test
	func `a spent nonce stays spent after relaunch`() async throws {
		let suite = try makeSuite()
		#expect(await makeSUT(suite).consume("n", expiresAt: clock.now + 600))

		let relaunched = makeSUT(suite)

		#expect(await !relaunched.consume("n", expiresAt: clock.now + 600))
		#expect(await relaunched.reserve("n", expiresAt: clock.now + 600) == nil)
	}

	@Test
	func `a committed reservation stays spent after relaunch`() async throws {
		let suite = try makeSuite()
		let store = makeSUT(suite)
		let reservation = try #require(await store.reserve("n", expiresAt: clock.now + 600))
		await store.commit(reservation)

		#expect(await !makeSUT(suite).consume("n", expiresAt: clock.now + 600))
	}

	@Test
	func `an open reservation is dropped on relaunch so the link can be retried`() async throws {
		let suite = try makeSuite()
		let store = makeSUT(suite)
		_ = try #require(await store.reserve("n", expiresAt: clock.now + 600))
		#expect(await store.reserve("n", expiresAt: clock.now + 600) == nil)

		#expect(await makeSUT(suite).reserve("n", expiresAt: clock.now + 600) != nil)
	}

	@Test
	func `a released reservation can be reserved again`() async throws {
		let store = try makeSUT(makeSuite())
		let reservation = try #require(await store.reserve("n", expiresAt: clock.now + 600))

		await store.release(reservation)

		#expect(await store.reserve("n", expiresAt: clock.now + 600) != nil)
	}

	@Test
	func `an abandoned reservation lapses after its time to live`() async throws {
		let store = try makeSUT(makeSuite(), reservationTTL: 30)
		_ = try #require(await store.reserve("n", expiresAt: clock.now + 600))

		clock.advance(by: 30)

		#expect(await store.reserve("n", expiresAt: clock.now + 600) != nil)
	}

	@Test
	func `expired nonces are forgotten and pruned from storage`() async throws {
		let suite = try makeSuite()
		let store = makeSUT(suite)
		_ = await store.consume("old", expiresAt: clock.now + 10)

		clock.advance(by: 10)
		_ = await store.consume("new", expiresAt: clock.now + 10)

		#expect(try storedNonces(in: suite) == ["new", "old"])
		clock.advance(by: 10)
		_ = await makeSUT(suite).consume("newest", expiresAt: clock.now + 10)
		#expect(try storedNonces(in: suite) == ["newest"])
	}

	@Test
	func `full store rejects new nonces instead of evicting live ones`() async throws {
		let store = try makeSUT(makeSuite(), maxEntries: 1)
		_ = await store.consume("a", expiresAt: clock.now + 600)

		#expect(await !store.consume("b", expiresAt: clock.now + 600))
	}

	@Test
	func `unreadable stored data starts an empty store`() async throws {
		let suite = try makeSuite()
		try #require(UserDefaults(suiteName: suite)).set(Data("not json".utf8), forKey: UserDefaultsNonceStore.defaultKey)

		#expect(await makeSUT(suite).consume("n", expiresAt: clock.now + 600))
	}

	@Test
	func `concurrent consumption of one nonce admits exactly one`() async throws {
		let store = try makeSUT(makeSuite())
		let expiry = clock.now + 600

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 50 {
				group.addTask { await store.consume("n", expiresAt: expiry) }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 1)
	}

	// MARK: - Helpers

	private func makeSuite() throws -> String {
		let suiteName = "nonces.\(UUID().uuidString)"
		cleanup.track(suiteName)
		return suiteName
	}

	/// A fresh `UserDefaults` per store: one instance cannot be sent to two actors.
	private func makeSUT(_ suiteName: String, maxEntries: Int = 100, reservationTTL: TimeInterval = 60) -> UserDefaultsNonceStore {
		UserDefaultsNonceStore(
			userDefaults: UserDefaults(suiteName: suiteName)!,
			maxEntries: maxEntries,
			reservationTTL: reservationTTL,
			dateProvider: clock.dateProvider,
		)
	}

	private func storedNonces(in suiteName: String) throws -> [String] {
		let data = try #require(UserDefaults(suiteName: suiteName)?.data(forKey: UserDefaultsNonceStore.defaultKey))
		let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
		let nonces = try #require(object["spent"] as? [String: Any])
		return nonces.keys.sorted()
	}
}
