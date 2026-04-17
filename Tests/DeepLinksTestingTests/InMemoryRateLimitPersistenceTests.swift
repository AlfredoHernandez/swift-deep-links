//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

struct InMemoryRateLimitPersistenceTests {
	@Test
	func `starts with no timestamps`() async {
		let sut = InMemoryRateLimitPersistence()

		let timestamps = await sut.loadRequests()

		#expect(timestamps.isEmpty)
	}

	@Test
	func `saves and loads timestamps`() async {
		let sut = InMemoryRateLimitPersistence()

		await sut.saveRequests([100, 200, 300])
		let loaded = await sut.loadRequests()

		#expect(loaded == [100, 200, 300])
	}

	@Test
	func `overwrites previously saved timestamps`() async {
		let sut = InMemoryRateLimitPersistence()

		await sut.saveRequests([100, 200])
		await sut.saveRequests([300])
		let loaded = await sut.loadRequests()

		#expect(loaded == [300])
	}

	@Test
	func `clears all timestamps`() async {
		let sut = InMemoryRateLimitPersistence()
		await sut.saveRequests([100, 200])

		await sut.clearRequests()
		let loaded = await sut.loadRequests()

		#expect(loaded.isEmpty)
	}
}
