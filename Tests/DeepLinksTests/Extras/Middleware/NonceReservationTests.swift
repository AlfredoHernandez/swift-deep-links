//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct NonceReservationTests {
	@Test
	func `a reserved nonce cannot be reserved or consumed again`() async throws {
		let (sut, clock) = makeSUT()

		let reservation = try #require(await sut.reserve("n", expiresAt: clock.now + 600))

		#expect(reservation.nonce == "n")
		#expect(await sut.reserve("n", expiresAt: clock.now + 600) == nil)
		#expect(await !sut.consume("n", expiresAt: clock.now + 600))
	}

	@Test
	func `releasing a reservation lets the nonce be used again`() async throws {
		let (sut, clock) = makeSUT()
		let reservation = try #require(await sut.reserve("n", expiresAt: clock.now + 600))

		await sut.release(reservation)

		#expect(await sut.reserve("n", expiresAt: clock.now + 600) != nil)
	}

	@Test
	func `committing a reservation spends the nonce until the link expires`() async throws {
		let (sut, clock) = makeSUT(reservationTTL: 30)
		let reservation = try #require(await sut.reserve("n", expiresAt: clock.now + 600))

		await sut.commit(reservation)
		clock.advance(by: 599)

		#expect(await sut.reserve("n", expiresAt: clock.now + 600) == nil)
		await sut.release(reservation)
		#expect(await sut.reserve("n", expiresAt: clock.now + 600) == nil)
	}

	@Test
	func `an abandoned reservation lapses after its time to live`() async throws {
		let (sut, clock) = makeSUT(reservationTTL: 30)
		_ = try #require(await sut.reserve("n", expiresAt: clock.now + 600))

		clock.advance(by: 29)
		#expect(await sut.reserve("n", expiresAt: clock.now + 600) == nil)

		clock.advance(by: 1)
		#expect(await sut.reserve("n", expiresAt: clock.now + 600) != nil)
	}

	@Test
	func `releasing a lapsed reservation does not free its successor`() async throws {
		let (sut, clock) = makeSUT(reservationTTL: 30)
		let stale = try #require(await sut.reserve("n", expiresAt: clock.now + 600))
		clock.advance(by: 30)
		_ = try #require(await sut.reserve("n", expiresAt: clock.now + 600))

		await sut.release(stale)

		#expect(await sut.reserve("n", expiresAt: clock.now + 600) == nil)
	}

	@Test
	func `concurrent reservations of one nonce admit exactly one`() async {
		let (sut, clock) = makeSUT()
		let expiry = clock.now + 600

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 50 {
				group.addTask { await sut.reserve("n", expiresAt: expiry) != nil }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 1)
	}

	@Test
	func `reservations count towards the bound`() async {
		let (sut, clock) = makeSUT(maxEntries: 1)
		_ = await sut.reserve("a", expiresAt: clock.now + 600)

		#expect(await sut.reserve("b", expiresAt: clock.now + 600) == nil)
	}

	@Test
	func `a consume-only store reserves by consuming`() async throws {
		let legacy = ConsumeOnlyNonceStore()

		let reservation = try #require(await legacy.reserve("n", expiresAt: .distantFuture))
		await legacy.release(reservation)

		#expect(legacy.consumed == ["n"])
		#expect(await legacy.reserve("n", expiresAt: .distantFuture) == nil)
	}
}

private func makeSUT(maxEntries: Int = 100, reservationTTL: TimeInterval = 60) -> (InMemoryNonceStore, ManualDateProvider) {
	let clock = ManualDateProvider()
	let store = InMemoryNonceStore(maxEntries: maxEntries, reservationTTL: reservationTTL, dateProvider: clock.dateProvider)
	return (store, clock)
}

/// A 1.x-style store implementing only `consume`.
private final class ConsumeOnlyNonceStore: NonceStore {
	private let seen = OSAllocatedUnfairLock<[String]>(initialState: [])

	var consumed: [String] {
		seen.withLock { $0 }
	}

	func consume(_ nonce: String, expiresAt _: Date) async -> Bool {
		seen.withLock { seen in
			guard !seen.contains(nonce) else { return false }
			seen.append(nonce)
			return true
		}
	}
}
