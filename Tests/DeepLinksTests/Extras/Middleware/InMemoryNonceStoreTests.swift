//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct InMemoryNonceStoreTests {
	@Test
	func `first use of a nonce is accepted and later uses are rejected`() async {
		let (sut, clock) = makeSUT()

		#expect(await sut.consume("n", expiresAt: clock.now + 60))
		#expect(await !sut.consume("n", expiresAt: clock.now + 60))
	}

	@Test
	func `distinct nonces are independent`() async {
		let (sut, clock) = makeSUT()

		#expect(await sut.consume("a", expiresAt: clock.now + 60))
		#expect(await sut.consume("b", expiresAt: clock.now + 60))
	}

	@Test
	func `nonce is forgotten once its expiry passes`() async {
		let (sut, clock) = makeSUT()
		_ = await sut.consume("n", expiresAt: clock.now + 60)

		clock.advance(by: 60)

		#expect(await sut.consume("n", expiresAt: clock.now + 60))
	}

	@Test
	func `full store rejects new nonces instead of evicting live ones`() async {
		let (sut, clock) = makeSUT(maxEntries: 2)
		_ = await sut.consume("a", expiresAt: clock.now + 60)
		_ = await sut.consume("b", expiresAt: clock.now + 60)

		#expect(await !sut.consume("c", expiresAt: clock.now + 60))
		#expect(await !sut.consume("a", expiresAt: clock.now + 60))
	}

	@Test
	func `expired entries free room in a full store`() async {
		let (sut, clock) = makeSUT(maxEntries: 1)
		_ = await sut.consume("a", expiresAt: clock.now + 10)

		clock.advance(by: 10)

		#expect(await sut.consume("b", expiresAt: clock.now + 10))
	}

	@Test
	func `already expired nonce is rejected`() async {
		let (sut, clock) = makeSUT()

		#expect(await !sut.consume("n", expiresAt: clock.now))
	}

	@Test
	func `concurrent consumption of one nonce admits exactly one`() async {
		let (sut, clock) = makeSUT()
		let expiry = clock.now + 60

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 50 {
				group.addTask { await sut.consume("n", expiresAt: expiry) }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 1)
	}
}

private func makeSUT(maxEntries: Int = 100) -> (InMemoryNonceStore, ManualDateProvider) {
	let clock = ManualDateProvider()
	return (InMemoryNonceStore(maxEntries: maxEntries, dateProvider: clock.dateProvider), clock)
}
