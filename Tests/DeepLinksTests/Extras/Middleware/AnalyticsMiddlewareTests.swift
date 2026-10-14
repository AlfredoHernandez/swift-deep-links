//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct AnalyticsMiddlewareTests {
	@Test
	func `AnalyticsMiddleware tracks deep link events with correct parameters`() async throws {
		let testURL = try #require(URL(string: "testapp://product?productId=456&category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsSpy)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)
	}

	@Test
	func `AnalyticsMiddleware handles URLs with unknown scheme and host`() async throws {
		let testURL = try #require(URL(string: "unknown://unknown"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsSpy)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["scheme"] as? String == "unknown")
		#expect(event.parameters["host"] as? String == "unknown")
	}

	// MARK: - Strategy Tests

	@Test
	func `AnalyticsMiddleware with detailed strategy tracks comprehensive URL information`() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics&price=299.99"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] as? String == "/123")
		#expect(event.parameters["timestamp"] as? Double != nil)

		if let queryParams = event.parameters["query_parameters"] as? [String: String] {
			#expect(queryParams["category"] == "electronics")
			#expect(queryParams["price"] == "299.99")
		} else {
			#expect(Bool(false), "Expected query parameters to be tracked")
		}
	}

	@Test
	func `AnalyticsMiddleware with minimal strategy tracks only essential information`() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics&price=299.99"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .minimal,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)

		#expect(event.parameters["url"] == nil)
		#expect(event.parameters["path"] == nil)
		#expect(event.parameters["query_parameters"] == nil)
	}

	@Test
	func `AnalyticsMiddleware with standard strategy tracks basic URL information`() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .standard,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)

		#expect(event.parameters["path"] == nil)
		#expect(event.parameters["query_parameters"] == nil)
		#expect(event.parameters["processing_time"] == nil)
	}

	// MARK: - Edge Cases

	@Test
	func `AnalyticsMiddleware with detailed strategy handles URLs without path`() async throws {
		let testURL = try #require(URL(string: "testapp://product?category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] == nil)

		if let queryParams = event.parameters["query_parameters"] as? [String: String] {
			#expect(queryParams["category"] == "electronics")
		} else {
			#expect(Bool(false), "Expected query parameters to be tracked")
		}
	}

	@Test
	func `AnalyticsMiddleware with detailed strategy handles URLs without query parameters`() async throws {
		let testURL = try #require(URL(string: "testapp://product/123"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] as? String == "/123")
		#expect(event.parameters["query_parameters"] == nil)
	}

	@Test
	func `AnalyticsMiddleware with detailed strategy handles URLs with empty path`() async throws {
		let testURL = try #require(URL(string: "testapp://product"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] == nil)
	}

	// MARK: - DefaultAnalyticsProvider Tests

	@Test
	func `DefaultAnalyticsProvider tracks events correctly`() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123"))
		let middleware = AnalyticsMiddleware(analyticsProvider: provider)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
	}

	@Test
	func `DefaultAnalyticsProvider works with all strategies`() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics"))

		let standardMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .standard,
		)
		let standardResult = try await standardMiddleware.intercept(url: testURL)
		#expect(standardResult == testURL)

		let detailedMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .detailed,
		)
		let detailedResult = try await detailedMiddleware.intercept(url: testURL)
		#expect(detailedResult == testURL)

		let minimalMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .minimal,
		)
		let minimalResult = try await minimalMiddleware.intercept(url: testURL)
		#expect(minimalResult == testURL)
	}

	@Test
	func `DefaultAnalyticsProvider is thread-safe`() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123"))

		await withTaskGroup(of: URL?.self) { group in
			for _ in 0 ..< 10 {
				group.addTask {
					let middleware = AnalyticsMiddleware(analyticsProvider: provider)
					return try! await middleware.intercept(url: testURL)
				}
			}

			var results: [URL?] = []
			for await result in group {
				results.append(result)
			}

			#expect(results.count == 10)
			#expect(results.allSatisfy { $0 == testURL })
		}
	}

	@Test
	func `DefaultAnalyticsProvider can be used as AnalyticsProvider protocol`() {
		let provider: AnalyticsProvider = DefaultAnalyticsProvider()

		provider.track("test_event", parameters: ["key": "value"])
	}
}
