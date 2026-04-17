//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct RateLimitMiddlewareTests {
	@Test
	func `intercept delivers URL within request limit`() async throws {
		let (sut, _) = makeSUT(maxRequests: 3)

		for _ in 0 ..< 3 {
			let result = try await sut.intercept(testURL)
			#expect(result == testURL)
		}
	}

	@Test
	func `intercept throws rate limit exceeded when over limit`() async throws {
		let (sut, _) = makeSUT(maxRequests: 2)

		for _ in 0 ..< 2 {
			_ = try await sut.intercept(testURL)
		}

		await #expect(throws: DeepLinkError.rateLimitExceeded(2, 60.0)) {
			try await sut.intercept(testURL)
		}
	}

	@Test
	func `intercept resets count after time window expires`() async throws {
		let (sut, _) = makeSUT(maxRequests: 1, timeWindow: 0.1)

		let result1 = try await sut.intercept(testURL)
		#expect(result1 == testURL)

		try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

		let result2 = try await sut.intercept(testURL)
		#expect(result2 == testURL)
	}

	@Test
	func `intercept persists state across middleware instances`() async throws {
		let persistence = try UserDefaultsRateLimitPersistence(
			userDefaults: #require(UserDefaults(suiteName: "test.ratelimit.\(UUID().uuidString)")),
			key: "test.requests.\(UUID().uuidString)",
		)

		let middleware1 = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		for _ in 0 ..< 2 {
			_ = try await middleware1.intercept(testURL)
		}

		let middleware2 = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		await #expect(throws: DeepLinkError.rateLimitExceeded(2, 60.0)) {
			try await middleware2.intercept(testURL)
		}
	}

	@Test
	func `intercept persists timestamps on successful requests`() async throws {
		let (sut, persistence) = makeSUT(maxRequests: 2)

		for _ in 0 ..< 2 {
			_ = try await sut.intercept(testURL)
		}

		let storedTimestamps = await persistence.loadRequests()
		#expect(storedTimestamps.count == 2)
	}

	// MARK: - Strategy Tests

	@Test
	func `intercept with sliding window tracks requests in rolling window`() async throws {
		let (sut, _) = makeSUT(maxRequests: 3, timeWindow: 1.0, strategy: .slidingWindow)

		for _ in 0 ..< 3 {
			let result = try await sut.intercept(testURL)
			#expect(result == testURL)
		}

		await #expect(throws: DeepLinkError.rateLimitExceeded(3, 1.0)) {
			try await sut.intercept(testURL)
		}
	}

	@Test
	func `intercept with sliding window removes old requests automatically`() async throws {
		let (sut, _) = makeSUT(maxRequests: 2, timeWindow: 0.2, strategy: .slidingWindow)

		for _ in 0 ..< 2 {
			_ = try await sut.intercept(testURL)
		}

		await #expect(throws: DeepLinkError.rateLimitExceeded(2, 0.2)) {
			try await sut.intercept(testURL)
		}

		try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

		let result = try await sut.intercept(testURL)
		#expect(result == testURL)
	}

	@Test
	func `intercept with fixed window resets at window boundaries`() async throws {
		let (sut, _) = makeSUT(maxRequests: 2, timeWindow: 1.0, strategy: .fixedWindow)

		for _ in 0 ..< 2 {
			_ = try await sut.intercept(testURL)
		}

		await #expect(throws: DeepLinkError.rateLimitExceeded(2, 1.0)) {
			try await sut.intercept(testURL)
		}

		try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

		let result = try await sut.intercept(testURL)
		#expect(result == testURL)
	}

	@Test
	func `intercept with fixed window allows full burst after window reset`() async throws {
		let (sut, _) = makeSUT(maxRequests: 2, timeWindow: 1.0, strategy: .fixedWindow)

		for _ in 0 ..< 2 {
			_ = try await sut.intercept(testURL)
		}

		try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

		for _ in 0 ..< 2 {
			let result = try await sut.intercept(testURL)
			#expect(result == testURL)
		}
	}

	@Test
	func `intercept with permissive strategy allows all requests`() async throws {
		let (sut, persistence) = makeSUT(maxRequests: 1, strategy: .permissive)

		for _ in 0 ..< 10 {
			let result = try await sut.intercept(testURL)
			#expect(result == testURL)
		}

		let storedTimestamps = await persistence.loadRequests()
		#expect(storedTimestamps.isEmpty)
	}

	@Test
	func `intercept with permissive strategy ignores impossible limits`() async throws {
		let persistence = InMemoryRateLimitPersistence()
		let sut = RateLimitMiddleware(
			maxRequests: 0,
			timeWindow: 0.0,
			persistence: persistence,
			strategy: .permissive,
		)

		let result = try await sut.intercept(testURL)
		#expect(result == testURL)
	}

	// MARK: - Helpers

	private var testURL: URL {
		URL(string: "testapp://test")!
	}

	private func makeSUT(
		maxRequests: Int = 100,
		timeWindow: TimeInterval = 60.0,
		strategy: RateLimitStrategy = .slidingWindow,
	) -> (sut: RateLimitMiddleware, persistence: InMemoryRateLimitPersistence) {
		let persistence = InMemoryRateLimitPersistence()
		let sut = RateLimitMiddleware(
			maxRequests: maxRequests,
			timeWindow: timeWindow,
			persistence: persistence,
			strategy: strategy,
		)
		return (sut, persistence)
	}
}
