//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("RateLimitPersistence Tests")
struct RateLimitPersistenceTests {
	@Test("UserDefaultsRateLimitPersistence saves and loads requests")
	func userDefaultsRateLimitPersistence_savesAndLoadsRequests() async throws {
		let userDefaults = try #require(UserDefaults(suiteName: "test.persistence"))
		let key = "test.requests"
		userDefaults.removeObject(forKey: key)

		let persistence = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: key)
		let testTimestamps: [TimeInterval] = [1_234_567_890.0, 1_234_567_891.0, 1_234_567_892.0]

		// Save requests
		await persistence.saveRequests(testTimestamps)

		// Load requests
		let loadedTimestamps = await persistence.loadRequests()

		#expect(loadedTimestamps == testTimestamps)

		// Clean up
		await persistence.clearRequests()
	}

	@Test("UserDefaultsRateLimitPersistence returns empty array when no data exists")
	func userDefaultsRateLimitPersistence_returnsEmptyArrayWhenNoDataExists() async throws {
		let userDefaults = try #require(UserDefaults(suiteName: "test.persistence.empty"))
		let key = "test.requests.empty"
		userDefaults.removeObject(forKey: key)

		let persistence = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: key)
		let loadedTimestamps = await persistence.loadRequests()

		#expect(loadedTimestamps.isEmpty)
	}

	@Test("UserDefaultsRateLimitPersistence clears requests")
	func userDefaultsRateLimitPersistence_clearsRequests() async throws {
		let userDefaults = try #require(UserDefaults(suiteName: "test.persistence.clear"))
		let key = "test.requests.clear"
		userDefaults.removeObject(forKey: key)

		let persistence = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: key)
		let testTimestamps: [TimeInterval] = [1_234_567_890.0, 1_234_567_891.0]

		// Save requests
		await persistence.saveRequests(testTimestamps)

		// Verify data exists
		let loadedTimestamps = await persistence.loadRequests()
		#expect(loadedTimestamps == testTimestamps)

		// Clear requests
		await persistence.clearRequests()

		// Verify data is cleared
		let clearedTimestamps = await persistence.loadRequests()
		#expect(clearedTimestamps.isEmpty)
	}

	@Test("UserDefaultsRateLimitPersistence handles invalid data gracefully")
	func userDefaultsRateLimitPersistence_handlesInvalidDataGracefully() async throws {
		let userDefaults = try #require(UserDefaults(suiteName: "test.persistence.invalid"))
		let key = "test.requests.invalid"
		userDefaults.removeObject(forKey: key)

		// Store invalid data
		let invalidData = "invalid json data".data(using: .utf8)!
		userDefaults.set(invalidData, forKey: key)

		let persistence = UserDefaultsRateLimitPersistence(userDefaults: userDefaults, key: key)
		let loadedTimestamps = await persistence.loadRequests()

		// Should return empty array for invalid data
		#expect(loadedTimestamps.isEmpty)

		// Clean up
		await persistence.clearRequests()
	}
}
