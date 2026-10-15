//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct RateLimitRetentionTests {
	private static let twoHours: TimeInterval = 7200
	private let cleanup = UserDefaultsSuiteCleanup()

	@Test(arguments: [RateLimitStrategy.slidingWindow, .fixedWindow])
	func `a window longer than maxAge keeps its requests`(strategy: RateLimitStrategy) async throws {
		let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_800_000_000))
		let persistence = try makePersistence(maxAge: 3600, clock: clock)
		let sut = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: Self.twoHours,
			persistence: persistence,
			strategy: strategy,
			dateProvider: clock.dateProvider,
		)
		let url = try #require(URL(string: "myapp://home"))

		_ = try await sut.intercept(url: url)
		clock.advance(by: 5400)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 1, timeWindow: Self.twoHours)) {
			_ = try await sut.intercept(url: url)
		}
		#expect(await persistence.loadRequests().count == 1)
	}

	@Test
	func `retention never drops below maxAge`() async throws {
		let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_800_000_000))
		let persistence = try makePersistence(maxAge: 3600, clock: clock)
		let now = clock.now.timeIntervalSince1970

		await persistence.mutateRequests(retaining: 60) { $0 = [now - 1800, now - 4000] }

		#expect(await persistence.loadRequests() == [now - 1800])
	}

	@Test
	func `a persistence without native retention support falls back to mutateRequests`() async {
		let persistence: any RateLimitPersistence = InMemoryRateLimitPersistence()

		let count = await persistence.mutateRequests(retaining: Self.twoHours) { timestamps in
			timestamps.append(1)
			return timestamps.count
		}

		#expect(count == 1)
		#expect(await persistence.loadRequests() == [1])
	}

	private func makePersistence(maxAge: TimeInterval, clock: ManualDateProvider) throws -> UserDefaultsRateLimitPersistence {
		let suiteName = "test.retention.\(UUID().uuidString)"
		cleanup.track(suiteName)
		return try UserDefaultsRateLimitPersistence(
			userDefaults: #require(UserDefaults(suiteName: suiteName)),
			maxAge: maxAge,
			dateProvider: clock.dateProvider,
		)
	}
}
