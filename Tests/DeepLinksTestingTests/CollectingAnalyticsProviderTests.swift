//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

@Suite("CollectingAnalyticsProvider")
struct CollectingAnalyticsProviderTests {
	@Test("starts with no events")
	func trackedEvents_deliversEmptyOnInit() {
		let sut = CollectingAnalyticsProvider()

		#expect(sut.trackedEvents.isEmpty)
	}

	@Test("collects event with name and string-converted parameters")
	func track_collectsEventWithParameters() {
		let sut = CollectingAnalyticsProvider()

		sut.track("deep_link_opened", parameters: ["url": "myapp://test", "count": 42])

		#expect(sut.trackedEvents.count == 1)
		#expect(sut.trackedEvents.first?.name == "deep_link_opened")
		#expect(sut.trackedEvents.first?.parameters["url"] == "myapp://test")
		#expect(sut.trackedEvents.first?.parameters["count"] == "42")
	}

	@Test("collects event with empty parameters")
	func track_collectsEventWithEmptyParameters() {
		let sut = CollectingAnalyticsProvider()

		sut.track("event", parameters: [:])

		#expect(sut.trackedEvents.count == 1)
		#expect(sut.trackedEvents.first?.parameters.isEmpty == true)
	}

	@Test("collects multiple events in order")
	func track_collectsMultipleEventsInOrder() {
		let sut = CollectingAnalyticsProvider()

		sut.track("first", parameters: [:])
		sut.track("second", parameters: [:])
		sut.track("third", parameters: [:])

		#expect(sut.trackedEvents.map(\.name) == ["first", "second", "third"])
	}

	@Test("is thread-safe under concurrent access")
	func track_collectsAllEventsUnderConcurrentAccess() async {
		let sut = CollectingAnalyticsProvider()

		await withTaskGroup(of: Void.self) { group in
			for i in 0 ..< 100 {
				group.addTask { sut.track("event_\(i)", parameters: [:]) }
			}
		}

		#expect(sut.trackedEvents.count == 100)
	}
}
