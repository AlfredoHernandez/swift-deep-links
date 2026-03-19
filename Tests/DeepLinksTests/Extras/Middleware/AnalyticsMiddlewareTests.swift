//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@Suite("AnalyticsMiddleware Tests")
struct AnalyticsMiddlewareTests {
	@Test("AnalyticsMiddleware tracks deep link events with correct parameters")
	func analyticsMiddleware_tracksDeepLinkEventsWithCorrectParameters() async throws {
		let testURL = try #require(URL(string: "testapp://product?productId=456&category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsSpy)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)
	}

	@Test("AnalyticsMiddleware handles URLs with unknown scheme and host")
	func analyticsMiddleware_handlesURLsWithUnknownSchemeAndHost() async throws {
		let testURL = try #require(URL(string: "unknown://unknown"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsSpy)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["scheme"] as? String == "unknown")
		#expect(event.parameters["host"] as? String == "unknown")
	}

	// MARK: - Strategy Tests

	@Test("AnalyticsMiddleware with detailed strategy tracks comprehensive URL information")
	func analyticsMiddleware_withDetailedStrategy_tracksComprehensiveURLInformation() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics&price=299.99"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] as? String == "/123")
		#expect(event.parameters["timestamp"] as? Double != nil)

		// Check query parameters
		if let queryParams = event.parameters["query_parameters"] as? [String: String] {
			#expect(queryParams["category"] == "electronics")
			#expect(queryParams["price"] == "299.99")
		} else {
			#expect(Bool(false), "Expected query parameters to be tracked")
		}
	}

	@Test("AnalyticsMiddleware with minimal strategy tracks only essential information")
	func analyticsMiddleware_withMinimalStrategy_tracksOnlyEssentialInformation() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics&price=299.99"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .minimal,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)

		// Should NOT track URL, path, or query parameters
		#expect(event.parameters["url"] == nil)
		#expect(event.parameters["path"] == nil)
		#expect(event.parameters["query_parameters"] == nil)
	}

	@Test("AnalyticsMiddleware with performance strategy tracks timing information")
	func analyticsMiddleware_withPerformanceStrategy_tracksTimingInformation() async throws {
		let testURL = try #require(URL(string: "testapp://product/123"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .performance,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)
		#expect(event.parameters["processing_time"] as? Double != nil)

		// Processing time should be a small positive number
		if let processingTime = event.parameters["processing_time"] as? Double {
			#expect(processingTime >= 0)
			#expect(processingTime < 1.0) // Should be very fast
		} else {
			#expect(Bool(false), "Expected processing_time to be tracked")
		}
	}

	@Test("AnalyticsMiddleware with standard strategy tracks basic URL information")
	func analyticsMiddleware_withStandardStrategy_tracksBasicURLInformation() async throws {
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.event == "deep_link_opened")
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["timestamp"] as? Double != nil)

		// Should NOT track path or query parameters (only basic info)
		#expect(event.parameters["path"] == nil)
		#expect(event.parameters["query_parameters"] == nil)
		#expect(event.parameters["processing_time"] == nil)
	}

	// MARK: - Edge Cases

	@Test("AnalyticsMiddleware with detailed strategy handles URLs without path")
	func analyticsMiddleware_withDetailedStrategy_handlesURLsWithoutPath() async throws {
		let testURL = try #require(URL(string: "testapp://product?category=electronics"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] == nil) // No path should be nil

		// Should still track query parameters
		if let queryParams = event.parameters["query_parameters"] as? [String: String] {
			#expect(queryParams["category"] == "electronics")
		} else {
			#expect(Bool(false), "Expected query parameters to be tracked")
		}
	}

	@Test("AnalyticsMiddleware with detailed strategy handles URLs without query parameters")
	func analyticsMiddleware_withDetailedStrategy_handlesURLsWithoutQueryParameters() async throws {
		let testURL = try #require(URL(string: "testapp://product/123"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] as? String == "/123")
		#expect(event.parameters["query_parameters"] == nil) // No query params should be nil
	}

	@Test("AnalyticsMiddleware with detailed strategy handles URLs with empty path")
	func analyticsMiddleware_withDetailedStrategy_handlesURLsWithEmptyPath() async throws {
		let testURL = try #require(URL(string: "testapp://product"))
		let analyticsSpy = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(
			analyticsProvider: analyticsSpy,
			strategy: .detailed,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsSpy.trackedEvents.count == 1)

		let event = analyticsSpy.trackedEvents[0]
		#expect(event.parameters["url"] as? String == testURL.absoluteString)
		#expect(event.parameters["scheme"] as? String == "testapp")
		#expect(event.parameters["host"] as? String == "product")
		#expect(event.parameters["path"] == nil) // Empty path should be nil
	}

	// MARK: - DefaultAnalyticsProvider Tests

	@Test("DefaultAnalyticsProvider tracks events correctly")
	func defaultAnalyticsProvider_tracksEventsCorrectly() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123"))
		let middleware = AnalyticsMiddleware(analyticsProvider: provider)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		// DefaultAnalyticsProvider logs to console, so we can't easily test the output
		// But we can verify it doesn't throw any errors
	}

	@Test("DefaultAnalyticsProvider works with all strategies")
	func defaultAnalyticsProvider_worksWithAllStrategies() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123?category=electronics"))

		// Test with standard strategy
		let standardMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .standard,
		)
		let standardResult = try await standardMiddleware.intercept(testURL)
		#expect(standardResult == testURL)

		// Test with detailed strategy
		let detailedMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .detailed,
		)
		let detailedResult = try await detailedMiddleware.intercept(testURL)
		#expect(detailedResult == testURL)

		// Test with minimal strategy
		let minimalMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .minimal,
		)
		let minimalResult = try await minimalMiddleware.intercept(testURL)
		#expect(minimalResult == testURL)

		// Test with performance strategy
		let performanceMiddleware = AnalyticsMiddleware(
			analyticsProvider: provider,
			strategy: .performance,
		)
		let performanceResult = try await performanceMiddleware.intercept(testURL)
		#expect(performanceResult == testURL)
	}

	@Test("DefaultAnalyticsProvider is thread-safe")
	func defaultAnalyticsProvider_isThreadSafe() async throws {
		let provider = DefaultAnalyticsProvider()
		let testURL = try #require(URL(string: "testapp://product/123"))

		// Test concurrent access
		await withTaskGroup(of: URL?.self) { group in
			for _ in 0 ..< 10 {
				group.addTask {
					let middleware = AnalyticsMiddleware(analyticsProvider: provider)
					return try! await middleware.intercept(testURL)
				}
			}

			var results: [URL?] = []
			for await result in group {
				results.append(result)
			}

			// All results should be the same URL
			#expect(results.count == 10)
			#expect(results.allSatisfy { $0 == testURL })
		}
	}

	@Test("DefaultAnalyticsProvider can be used as AnalyticsProvider protocol")
	func defaultAnalyticsProvider_canBeUsedAsAnalyticsProviderProtocol() {
		let provider: AnalyticsProvider = DefaultAnalyticsProvider()

		// Test that it can be used as protocol
		provider.track("test_event", parameters: ["key": "value"])
		// If no error is thrown, the test passes
	}
}
