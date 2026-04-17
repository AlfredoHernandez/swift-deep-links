//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct CollectingDelegateTests {
	@Test
	func `starts with no events`() {
		let sut = CollectingDelegate()

		#expect(sut.willProcessURLs.isEmpty)
		#expect(sut.processedEvents.isEmpty)
		#expect(sut.failedEvents.isEmpty)
	}

	@Test
	func `collects willProcess URLs in order`() {
		let sut = CollectingDelegate()

		sut.coordinator(NSObject(), willProcess: testURL)
		sut.coordinator(NSObject(), willProcess: anotherURL)

		#expect(sut.willProcessURLs == [testURL, anotherURL])
	}

	@Test
	func `collects didProcess events with result data`() {
		let sut = CollectingDelegate()
		let result = DeepLinkResult<TestRoute>(
			originalURL: testURL,
			processedURL: testURL,
			routes: [.routeA],
			executionTime: 0.1,
			successfulRoutes: 1,
		)

		sut.coordinator(NSObject(), didProcess: testURL, result: result)

		#expect(sut.processedEvents.count == 1)
		#expect(sut.processedEvents.first?.url == testURL)
		#expect(sut.processedEvents.first?.result.wasSuccessful == true)
		#expect(sut.processedEvents.first?.result.successfulRoutes == 1)
		#expect(sut.processedEvents.first?.result.executionTime == 0.1)
	}

	@Test
	func `collects multiple didProcess events in order`() {
		let sut = CollectingDelegate()
		let result1 = DeepLinkResult<TestRoute>(originalURL: testURL, processedURL: testURL, routes: [.routeA], executionTime: 0.1)
		let result2 = DeepLinkResult<TestRoute>(originalURL: anotherURL, processedURL: anotherURL, routes: [.routeB], executionTime: 0.2)

		sut.coordinator(NSObject(), didProcess: testURL, result: result1)
		sut.coordinator(NSObject(), didProcess: anotherURL, result: result2)

		#expect(sut.processedEvents.count == 2)
		#expect(sut.processedEvents[0].url == testURL)
		#expect(sut.processedEvents[1].url == anotherURL)
	}

	@Test
	func `collects didFailProcessing events with error`() {
		let sut = CollectingDelegate()
		let error = DeepLinkError.routeNotFound("test")

		sut.coordinator(NSObject(), didFailProcessing: testURL, error: error)

		#expect(sut.failedEvents.count == 1)
		#expect(sut.failedEvents.first?.url == testURL)
		#expect(sut.failedEvents.first?.error as? DeepLinkError == .routeNotFound("test"))
	}

	@Test
	func `collects multiple didFailProcessing events in order`() {
		let sut = CollectingDelegate()

		sut.coordinator(NSObject(), didFailProcessing: testURL, error: DeepLinkError.routeNotFound("a"))
		sut.coordinator(NSObject(), didFailProcessing: anotherURL, error: DeepLinkError.routeNotFound("b"))

		#expect(sut.failedEvents.count == 2)
		#expect(sut.failedEvents[0].url == testURL)
		#expect(sut.failedEvents[1].url == anotherURL)
	}
}
