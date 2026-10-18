//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct CollectingDelegateTests {
	@Test
	func `starts with no events`() {
		let sut = CollectingDelegate<TestRoute>()

		#expect(sut.willProcessURLs.isEmpty)
		#expect(sut.processedEvents.isEmpty)
		#expect(sut.failedEvents.isEmpty)
	}

	@Test
	func `collects willProcess URLs in order`() async throws {
		let sut = CollectingDelegate<TestRoute>()
		let coordinator = try await makeCoordinator(delegate: sut)

		sut.coordinator(coordinator, willProcess: testURL)
		sut.coordinator(coordinator, willProcess: anotherURL)

		#expect(sut.willProcessURLs == [testURL, anotherURL])
	}

	@Test
	func `collects didProcess events with result data`() async throws {
		let sut = CollectingDelegate<TestRoute>()
		let coordinator = try await makeCoordinator(delegate: sut)
		let result = DeepLinkResult<TestRoute>(
			originalURL: testURL,
			processedURL: testURL,
			routes: [.routeA],
			executionTime: 0.1,
			successfulRoutes: 1,
		)

		sut.coordinator(coordinator, didProcess: testURL, result: result)

		#expect(sut.processedEvents.count == 1)
		#expect(sut.processedEvents.first?.url == testURL)
		#expect(sut.processedEvents.first?.result.wasSuccessful == true)
		#expect(sut.processedEvents.first?.result.successfulRoutes == 1)
		#expect(sut.processedEvents.first?.result.executionTime == 0.1)
	}

	@Test
	func `collects multiple didProcess events in order`() async throws {
		let sut = CollectingDelegate<TestRoute>()
		let coordinator = try await makeCoordinator(delegate: sut)
		let result1 = DeepLinkResult<TestRoute>(originalURL: testURL, processedURL: testURL, routes: [.routeA], executionTime: 0.1)
		let result2 = DeepLinkResult<TestRoute>(originalURL: anotherURL, processedURL: anotherURL, routes: [.routeB], executionTime: 0.2)

		sut.coordinator(coordinator, didProcess: testURL, result: result1)
		sut.coordinator(coordinator, didProcess: anotherURL, result: result2)

		#expect(sut.processedEvents.count == 2)
		#expect(sut.processedEvents[0].url == testURL)
		#expect(sut.processedEvents[1].url == anotherURL)
	}

	@Test
	func `collects didFailProcessing events with error`() async throws {
		let sut = CollectingDelegate<TestRoute>()
		let coordinator = try await makeCoordinator(delegate: sut)
		let error = DeepLinkError.routeNotFound(testURL)

		sut.coordinator(coordinator, didFailProcessing: testURL, error: error)

		#expect(sut.failedEvents.count == 1)
		#expect(sut.failedEvents.first?.url == testURL)
		#expect(sut.failedEvents.first?.error as? DeepLinkError == .routeNotFound(testURL))
	}

	@Test
	func `collects multiple didFailProcessing events in order`() async throws {
		let sut = CollectingDelegate<TestRoute>()
		let coordinator = try await makeCoordinator(delegate: sut)

		sut.coordinator(coordinator, didFailProcessing: testURL, error: DeepLinkError.routeNotFound(testURL))
		sut.coordinator(coordinator, didFailProcessing: anotherURL, error: DeepLinkError.routeNotFound(anotherURL))

		#expect(sut.failedEvents.count == 2)
		#expect(sut.failedEvents[0].url == testURL)
		#expect(sut.failedEvents[1].url == anotherURL)
	}

	// MARK: - Helpers

	private func makeCoordinator(delegate: CollectingDelegate<TestRoute>) async throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(StubRouting())
			.handler(StubHandler())
			.delegate(delegate)
			.build()
	}

	private struct StubRouting: DeepLinkRouting {
		func route(from _: URL) async throws -> [TestRoute] {
			[]
		}
	}

	private struct StubHandler: DeepLinkHandler {
		func handle(_: TestRoute) async throws {}
	}
}
