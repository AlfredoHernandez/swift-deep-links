//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

@Suite("InMemoryRateLimitPersistence")
struct InMemoryRateLimitPersistenceTests {
	@Test("starts with no timestamps")
	func loadRequests_deliversEmptyOnInit() async {
		let sut = InMemoryRateLimitPersistence()

		let timestamps = await sut.loadRequests()

		#expect(timestamps.isEmpty)
	}

	@Test("saves and loads timestamps")
	func saveRequests_persistsTimestampsForRetrieval() async {
		let sut = InMemoryRateLimitPersistence()

		await sut.saveRequests([100, 200, 300])
		let loaded = await sut.loadRequests()

		#expect(loaded == [100, 200, 300])
	}

	@Test("overwrites previously saved timestamps")
	func saveRequests_overwritesPreviousTimestamps() async {
		let sut = InMemoryRateLimitPersistence()

		await sut.saveRequests([100, 200])
		await sut.saveRequests([300])
		let loaded = await sut.loadRequests()

		#expect(loaded == [300])
	}

	@Test("clears all timestamps")
	func clearRequests_removesAllTimestamps() async {
		let sut = InMemoryRateLimitPersistence()
		await sut.saveRequests([100, 200])

		await sut.clearRequests()
		let loaded = await sut.loadRequests()

		#expect(loaded.isEmpty)
	}
}
