//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import DeepLinksTesting
import Testing

struct CollectingMiddlewareTests {
	@Test
	func `starts with no intercepted URLs`() {
		let sut = CollectingMiddleware()

		#expect(sut.interceptedURLs.isEmpty)
	}

	@Test
	func `passes URL through and collects it`() async throws {
		let sut = CollectingMiddleware()

		let result = try await sut.intercept(url: testURL)

		#expect(result == testURL)
		#expect(sut.interceptedURLs == [testURL])
	}

	@Test
	func `passes a request through and collects it with its context`() async throws {
		let sut = CollectingMiddleware()
		let request = DeepLinkRequest(url: testURL, context: DeepLinkContext(source: .notification))

		let result = try await sut.intercept(request)

		#expect(result == request)
		#expect(sut.interceptedRequests == [request])
		#expect(sut.interceptedURLs == [testURL])
	}

	@Test
	func `collects multiple URLs in order`() async throws {
		let sut = CollectingMiddleware()

		_ = try await sut.intercept(url: testURL)
		_ = try await sut.intercept(url: anotherURL)

		#expect(sut.interceptedURLs == [testURL, anotherURL])
	}

	@Test
	func `is thread-safe under concurrent access`() async {
		let sut = CollectingMiddleware()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 100 {
				group.addTask { _ = try? await sut.intercept(url: testURL) }
			}
		}

		#expect(sut.interceptedURLs.count == 100)
	}
}

struct PassthroughMiddlewareTests {
	@Test
	func `always returns the same URL unchanged`() async throws {
		let sut = PassthroughMiddleware()

		let result1 = try await sut.intercept(url: testURL)
		let result2 = try await sut.intercept(url: anotherURL)

		#expect(result1 == testURL)
		#expect(result2 == anotherURL)
	}
}
