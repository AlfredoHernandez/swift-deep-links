//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

struct CollectingAnalyticsProviderTests {
	@Test
	func `starts with no events`() {
		let sut = CollectingAnalyticsProvider()

		#expect(sut.trackedEvents.isEmpty)
	}

	@Test
	func `collects event with name and string-converted parameters`() {
		let sut = CollectingAnalyticsProvider()

		sut.track("deep_link_opened", parameters: ["url": "myapp://test", "count": 42])

		#expect(sut.trackedEvents.count == 1)
		#expect(sut.trackedEvents.first?.name == "deep_link_opened")
		#expect(sut.trackedEvents.first?.parameters["url"] == "myapp://test")
		#expect(sut.trackedEvents.first?.parameters["count"] == "42")
	}

	@Test
	func `collects event with empty parameters`() {
		let sut = CollectingAnalyticsProvider()

		sut.track("event", parameters: [:])

		#expect(sut.trackedEvents.count == 1)
		#expect(sut.trackedEvents.first?.parameters.isEmpty == true)
	}

	@Test
	func `collects multiple events in order`() {
		let sut = CollectingAnalyticsProvider()

		sut.track("first", parameters: [:])
		sut.track("second", parameters: [:])
		sut.track("third", parameters: [:])

		#expect(sut.trackedEvents.map(\.name) == ["first", "second", "third"])
	}

	@Test
	func `is thread-safe under concurrent access`() async {
		let sut = CollectingAnalyticsProvider()

		await withTaskGroup(of: Void.self) { group in
			for i in 0 ..< 100 {
				group.addTask { sut.track("event_\(i)", parameters: [:]) }
			}
		}

		#expect(sut.trackedEvents.count == 100)
	}
}
