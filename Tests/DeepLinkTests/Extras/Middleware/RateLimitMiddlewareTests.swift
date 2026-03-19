//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("RateLimitMiddleware Tests")
struct RateLimitMiddlewareTests {
	@Test("RateLimitMiddleware allows requests within limit")
	func rateLimitMiddleware_allowsRequestsWithinLimit() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 3,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Make 3 requests (within limit)
		for _ in 0 ..< 3 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}
	}

	@Test("RateLimitMiddleware blocks requests exceeding limit")
	func rateLimitMiddleware_blocksRequestsExceedingLimit() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 60.0))
		}
	}

	@Test("RateLimitMiddleware resets count after time window")
	func rateLimitMiddleware_resetsCountAfterTimeWindow() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: 0.1, // Very short window
			persistence: persistence,
		)

		// First request should succeed
		let result1 = try await middleware.intercept(testURL)
		#expect(result1 == testURL)

		// Wait for time window to expire
		try await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

		// Second request should now succeed
		let result2 = try await middleware.intercept(testURL)
		#expect(result2 == testURL)
	}

	@Test("RateLimitMiddleware persists state across instances")
	func rateLimitMiddleware_persistsStateAcrossInstances() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let userDefaults = try #require(UserDefaults(suiteName: "test.ratelimit"))
		let requestsKey = "test.requests"

		// Clear any existing data
		userDefaults.removeObject(forKey: requestsKey)

		// Create shared persistence for both instances
		let persistence = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: requestsKey)

		// Create first middleware instance and make requests
		let middleware1 = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware1.intercept(testURL)
			#expect(result == testURL)
		}

		// Create second middleware instance (simulating app restart)
		let middleware2 = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Third request should be blocked (rate limit exceeded)
		do {
			_ = try await middleware2.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 60.0))
		}

		// Clean up
		await persistence.clearRequests()
	}

	@Test("RateLimitMiddleware accepts custom queue")
	func rateLimitMiddleware_acceptsCustomQueue() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()

		let middleware = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// First request should succeed
		let result = try await middleware.intercept(testURL)
		#expect(result == testURL)

		// Second request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(1, 60.0))
		}
	}

	@Test("RateLimitMiddleware works with custom persistence implementation")
	func rateLimitMiddleware_worksWithCustomPersistenceImplementation() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let customPersistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: customPersistence,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 60.0))
		}

		// Verify persistence was used
		let storedTimestamps = await customPersistence.loadRequests()
		#expect(storedTimestamps.count == 2)
	}

	// MARK: - Strategy Tests

	@Test("SlidingWindow strategy tracks requests in rolling window")
	func slidingWindowStrategy_tracksRequestsInRollingWindow() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 3,
			timeWindow: 1.0, // 1 second window
			persistence: persistence,
			strategy: .slidingWindow,
		)

		// Make 3 requests (within limit)
		for _ in 0 ..< 3 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Fourth request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(3, 1.0))
		}
	}

	@Test("SlidingWindow strategy removes old requests automatically")
	func slidingWindowStrategy_removesOldRequestsAutomatically() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 0.2, // Very short window
			persistence: persistence,
			strategy: .slidingWindow,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 0.2))
		}

		// Wait for window to slide
		try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds

		// Now should allow requests again
		let result = try await middleware.intercept(testURL)
		#expect(result == testURL)
	}

	@Test("FixedWindow strategy resets at window boundaries")
	func fixedWindowStrategy_resetsAtWindowBoundaries() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 1.0, // 1 second fixed window
			persistence: persistence,
			strategy: .fixedWindow,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 1.0))
		}

		// Wait for fixed window to reset (just over 1 second)
		try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

		// Should allow requests again at new window boundary
		let result = try await middleware.intercept(testURL)
		#expect(result == testURL)
	}

	@Test("FixedWindow strategy allows burst at window transitions")
	func fixedWindowStrategy_allowsBurstAtWindowTransitions() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 1.0, // 1 second fixed window
			persistence: persistence,
			strategy: .fixedWindow,
		)

		// Use up the limit in current window
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Wait for window to reset
		try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1 seconds

		// Should allow full burst again (characteristic of fixed window)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}
	}

	@Test("Permissive strategy allows all requests")
	func permissiveStrategy_allowsAllRequests() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 1, // Very restrictive limit
			timeWindow: 60.0,
			persistence: persistence,
			strategy: .permissive,
		)

		// Should allow unlimited requests despite restrictive settings
		for _ in 0 ..< 10 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Verify no persistence operations were performed
		let storedTimestamps = await persistence.loadRequests()
		#expect(storedTimestamps.isEmpty)
	}

	@Test("Permissive strategy ignores rate limit settings")
	func permissiveStrategy_ignoresRateLimitSettings() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 0, // Impossible limit
			timeWindow: 0.0, // Invalid window
			persistence: persistence,
			strategy: .permissive,
		)

		// Should still allow requests despite impossible settings
		let result = try await middleware.intercept(testURL)
		#expect(result == testURL)
	}

	@Test("Strategy comparison: slidingWindow vs fixedWindow basic behavior")
	func strategyComparison_slidingWindowVsFixedWindowBasicBehavior() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence1 = InMemoryRateLimitPersistence()
		let persistence2 = InMemoryRateLimitPersistence()

		let slidingMiddleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 1.0,
			persistence: persistence1,
			strategy: .slidingWindow,
		)

		let fixedMiddleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 1.0,
			persistence: persistence2,
			strategy: .fixedWindow,
		)

		// Both should allow 2 requests initially
		for _ in 0 ..< 2 {
			let slidingResult = try await slidingMiddleware.intercept(testURL)
			let fixedResult = try await fixedMiddleware.intercept(testURL)
			#expect(slidingResult == testURL)
			#expect(fixedResult == testURL)
		}

		// Both should block the third request
		do {
			_ = try await slidingMiddleware.intercept(testURL)
			#expect(Bool(false), "Expected sliding window to block")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 1.0))
		}

		do {
			_ = try await fixedMiddleware.intercept(testURL)
			#expect(Bool(false), "Expected fixed window to block")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 1.0))
		}

		// Both strategies should behave the same initially
		// The key difference is in how they handle window resets over time
		// This test verifies that both strategies correctly enforce rate limits
	}
}
