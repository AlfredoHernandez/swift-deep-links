//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct RateLimitPersistenceTests {
	private static let fixedDate = Date(timeIntervalSince1970: 1_234_568_000.0)

	@Test
	func `loadRequests delivers previously saved timestamps`() async {
		let sut = makeSUT()
		let testTimestamps: [TimeInterval] = [1_234_567_890.0, 1_234_567_891.0, 1_234_567_892.0]

		await sut.saveRequests(testTimestamps)

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps == testTimestamps)
	}

	@Test
	func `loadRequests delivers empty on no stored data`() async {
		let sut = makeSUT()

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps.isEmpty)
	}

	@Test
	func `loadRequests delivers empty on invalid stored data`() async throws {
		let key = "test.requests.\(UUID().uuidString)"
		let userDefaults = try #require(UserDefaults(suiteName: "test.persistence.\(UUID().uuidString)"))
		let invalidData = "invalid json data".data(using: .utf8)!
		userDefaults.set(invalidData, forKey: key)

		let sut = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: key)
		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps.isEmpty)
	}

	@Test
	func `clearRequests removes all stored timestamps`() async {
		let sut = makeSUT()
		await sut.saveRequests([1_234_567_890.0, 1_234_567_891.0])

		await sut.clearRequests()

		let loadedTimestamps = await sut.loadRequests()
		#expect(loadedTimestamps.isEmpty)
	}

	// MARK: - Pruning Tests

	@Test
	func `loadRequests prunes expired timestamps`() async {
		let now = Self.fixedDate
		let sut = makeSUT(maxAge: 60, dateProvider: { now })

		let expiredTimestamp = now.timeIntervalSince1970 - 120 // 2 minutes ago
		let validTimestamp = now.timeIntervalSince1970 - 30 // 30 seconds ago

		await sut.saveRequests([expiredTimestamp, validTimestamp])

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps == [validTimestamp])
	}

	@Test
	func `loadRequests delivers empty when all timestamps expired`() async {
		let now = Self.fixedDate
		let sut = makeSUT(maxAge: 60, dateProvider: { now })

		let expiredTimestamps: [TimeInterval] = [
			now.timeIntervalSince1970 - 300,
			now.timeIntervalSince1970 - 200,
			now.timeIntervalSince1970 - 100,
		]

		await sut.saveRequests(expiredTimestamps)

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps.isEmpty)
	}

	@Test
	func `loadRequests keeps all timestamps when none expired`() async {
		let now = Self.fixedDate
		let sut = makeSUT(maxAge: 3600, dateProvider: { now })

		let recentTimestamps: [TimeInterval] = [
			now.timeIntervalSince1970 - 10,
			now.timeIntervalSince1970 - 5,
			now.timeIntervalSince1970 - 1,
		]

		await sut.saveRequests(recentTimestamps)

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps == recentTimestamps)
	}

	@Test
	func `loadRequests prunes timestamp exactly at maxAge boundary`() async {
		let now = Self.fixedDate
		let sut = makeSUT(maxAge: 60, dateProvider: { now })

		let exactBoundaryTimestamp = now.timeIntervalSince1970 - 60 // exactly maxAge ago
		let validTimestamp = now.timeIntervalSince1970 - 30

		await sut.saveRequests([exactBoundaryTimestamp, validTimestamp])

		let loadedTimestamps = await sut.loadRequests()

		#expect(loadedTimestamps == [validTimestamp], "Timestamp exactly at maxAge should be pruned (strict > comparison)")
	}

	// MARK: - Helpers

	private func makeSUT(
		maxAge: TimeInterval = 3600,
		dateProvider: @escaping @Sendable () -> Date = { fixedDate },
	) -> UserDefaultsRateLimitPersistence {
		let key = "test.requests.\(UUID().uuidString)"
		return UserDefaultsRateLimitPersistence(
			userDefaults: UserDefaults(suiteName: "test.persistence.\(UUID().uuidString)")!,
			key: key,
			maxAge: maxAge,
			dateProvider: dateProvider,
		)
	}
}
