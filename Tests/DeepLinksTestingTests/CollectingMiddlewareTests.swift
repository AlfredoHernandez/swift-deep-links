//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Testing

@Suite("CollectingMiddleware")
struct CollectingMiddlewareTests {
	@Test("starts with no intercepted URLs")
	func interceptedURLs_deliversEmptyOnInit() {
		let sut = CollectingMiddleware()

		#expect(sut.interceptedURLs.isEmpty)
	}

	@Test("passes URL through and collects it")
	func intercept_returnsURLAndCollectsIt() async throws {
		let sut = CollectingMiddleware()

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
		#expect(sut.interceptedURLs == [testURL])
	}

	@Test("collects multiple URLs in order")
	func intercept_collectsURLsInOrder() async throws {
		let sut = CollectingMiddleware()

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		#expect(sut.interceptedURLs == [testURL, anotherURL])
	}

	@Test("is thread-safe under concurrent access")
	func intercept_collectsAllURLsUnderConcurrentAccess() async {
		let sut = CollectingMiddleware()

		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 100 {
				group.addTask { _ = try? await sut.intercept(testURL) }
			}
		}

		#expect(sut.interceptedURLs.count == 100)
	}
}

@Suite("PassthroughMiddleware")
struct PassthroughMiddlewareTests {
	@Test("always returns the same URL unchanged")
	func intercept_returnsSameURL() async throws {
		let sut = PassthroughMiddleware()

		let result1 = try await sut.intercept(testURL)
		let result2 = try await sut.intercept(anotherURL)

		#expect(result1 == testURL)
		#expect(result2 == anotherURL)
	}
}
