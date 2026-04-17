//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

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

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
		#expect(sut.interceptedURLs == [testURL])
	}

	@Test
	func `collects multiple URLs in order`() async throws {
		let sut = CollectingMiddleware()

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		#expect(sut.interceptedURLs == [testURL, anotherURL])
	}

	@Test
	func `is thread-safe under concurrent access`() async {
		let sut = CollectingMiddleware()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 100 {
				group.addTask { _ = try? await sut.intercept(testURL) }
			}
		}

		#expect(sut.interceptedURLs.count == 100)
	}
}

struct PassthroughMiddlewareTests {
	@Test
	func `always returns the same URL unchanged`() async throws {
		let sut = PassthroughMiddleware()

		let result1 = try await sut.intercept(testURL)
		let result2 = try await sut.intercept(anotherURL)

		#expect(result1 == testURL)
		#expect(result2 == anotherURL)
	}
}
