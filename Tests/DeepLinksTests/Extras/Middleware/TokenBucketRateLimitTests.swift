//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct TokenBucketRateLimitTests {
	@Test
	func `admits a burst up to capacity at the same instant`() async throws {
		let (sut, _) = makeSUT(capacity: 3, refillRate: 1)

		for _ in 0 ..< 3 {
			#expect(try await sut.intercept(url: testURL) == testURL)
		}
	}

	@Test
	func `rejects the request after the burst with capacity and full refill time`() async throws {
		let (sut, _) = makeSUT(capacity: 3, refillRate: 1)
		try await exhaust(sut, times: 3)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 3, timeWindow: 3)) {
			try await sut.intercept(url: testURL)
		}
	}

	@Test
	func `refills one token per refill interval`() async throws {
		let (sut, clock) = makeSUT(capacity: 2, refillRate: 2)
		try await exhaust(sut, times: 2)

		clock.advance(by: 0.25)
		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }

		clock.advance(by: 0.25)
		#expect(try await sut.intercept(url: testURL) == testURL)
		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test
	func `refill never exceeds capacity after a long idle period`() async throws {
		let (sut, clock) = makeSUT(capacity: 2, refillRate: 1)
		try await exhaust(sut, times: 2)

		clock.advance(by: 10000)

		try await exhaust(sut, times: 2)
		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test
	func `fractional refill intervals admit the full burst without rounding loss`() async throws {
		let (sut, clock) = makeSUT(capacity: 10, refillRate: 10)
		try await exhaust(sut, times: 10)

		clock.advance(by: 1)

		try await exhaust(sut, times: 10)
		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test
	func `zero capacity rejects every request`() async {
		let (sut, _) = makeSUT(capacity: 0, refillRate: 1)

		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test(arguments: [0, -1, Double.nan])
	func `non positive refill rate never refills`(refillRate: Double) async throws {
		let (sut, clock) = makeSUT(capacity: 2, refillRate: refillRate)
		try await exhaust(sut, times: 2)

		clock.advance(by: 1_000_000)

		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test
	func `non refilling bucket reports the span since its first admitted request`() async throws {
		let (sut, clock) = makeSUT(capacity: 2, refillRate: 0)
		try await exhaust(sut, times: 1)
		clock.advance(by: 30)
		try await exhaust(sut, times: 1)

		clock.advance(by: 90)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 2, timeWindow: 120)) {
			try await sut.intercept(url: testURL)
		}
	}

	@Test
	func `zero capacity without refill reports a zero window`() async {
		let (sut, _) = makeSUT(capacity: 0, refillRate: 0)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 0, timeWindow: 0)) {
			try await sut.intercept(url: testURL)
		}
	}

	@Test
	func `refill rate too small for a finite interval never refills`() async throws {
		let (sut, clock) = makeSUT(capacity: 2, refillRate: 1e-320)
		try await exhaust(sut, times: 2)

		clock.advance(by: 1_000_000)

		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }
	}

	@Test
	func `infinite refill rate never limits`() async throws {
		let (sut, _) = makeSUT(capacity: 1, refillRate: .infinity)

		try await exhaust(sut, times: 100)
	}

	@Test
	func `ignores the middleware request count and time window`() async throws {
		let clock = ManualDateProvider()
		let sut = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: 3600,
			persistence: InMemoryRateLimitPersistence(),
			strategy: .tokenBucket(capacity: 3, refillRate: 1),
			dateProvider: clock.dateProvider,
		)

		try await exhaust(sut, times: 3)
	}

	@Test
	func `clock moved backwards waits at most one refill interval`() async throws {
		let (sut, clock) = makeSUT(capacity: 1, refillRate: 1)
		try await exhaust(sut, times: 1)

		clock.advance(by: -1000)
		await #expect(throws: DeepLinkError.self) { try await sut.intercept(url: testURL) }

		clock.advance(by: 1)
		#expect(try await sut.intercept(url: testURL) == testURL)
	}

	@Test
	func `stale timestamps from another strategy start with a full bucket`() async throws {
		let persistence = InMemoryRateLimitPersistence()
		let clock = ManualDateProvider()
		let past = clock.dateProvider().timeIntervalSince1970 - 120
		await persistence.saveRequests([past, past + 1, past + 2])
		let sut = makeMiddleware(capacity: 3, refillRate: 1, persistence: persistence, clock: clock)

		try await exhaust(sut, times: 3)
	}

	@Test
	func `bucket state persists across middleware instances sharing persistence`() async throws {
		let persistence = InMemoryRateLimitPersistence()
		let clock = ManualDateProvider()
		try await exhaust(makeMiddleware(capacity: 2, refillRate: 1, persistence: persistence, clock: clock), times: 2)

		let second = makeMiddleware(capacity: 2, refillRate: 1, persistence: persistence, clock: clock)

		await #expect(throws: DeepLinkError.self) { try await second.intercept(url: testURL) }
	}

	@Test
	func `concurrent requests never exceed capacity`() async {
		let (sut, _) = makeSUT(capacity: 5, refillRate: 1)

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 50 {
				group.addTask { await (try? sut.intercept(url: testURL)) != nil }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 5)
	}

	// MARK: - Helpers

	private func makeSUT(capacity: Int, refillRate: Double) -> (sut: RateLimitMiddleware, clock: ManualDateProvider) {
		let clock = ManualDateProvider()
		let sut = makeMiddleware(capacity: capacity, refillRate: refillRate, persistence: InMemoryRateLimitPersistence(), clock: clock)
		return (sut, clock)
	}

	private func makeMiddleware(
		capacity: Int,
		refillRate: Double,
		persistence: RateLimitPersistence,
		clock: ManualDateProvider,
	) -> RateLimitMiddleware {
		RateLimitMiddleware(
			persistence: persistence,
			strategy: .tokenBucket(capacity: capacity, refillRate: refillRate),
			dateProvider: clock.dateProvider,
		)
	}

	private func exhaust(_ sut: RateLimitMiddleware, times: Int) async throws {
		for _ in 0 ..< times {
			#expect(try await sut.intercept(url: testURL) == testURL)
		}
	}
}

private let testURL = URL(string: "testapp://bucket")!
