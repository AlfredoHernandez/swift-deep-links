//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@Suite("ReadinessMiddleware Tests")
struct ReadinessMiddlewareTests {
	private let testURL = URL(string: "myapp://test")!
	private let anotherURL = URL(string: "myapp://other")!

	// MARK: - Queue Tests

	@Test("When ready, URL passes through immediately")
	func whenReady_urlPassesThrough() async throws {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()
		let sut = ReadinessMiddleware(queue: queue)

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
	}

	@Test("When not ready, URL is queued and nil is returned")
	func whenNotReady_urlIsQueuedAndReturnsNil() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		let result = try await sut.intercept(testURL)

		#expect(result == nil)
		#expect(queue.pendingCount == 1)
	}

	@Test("Multiple URLs are queued when not ready")
	func multipleURLsQueuedWhenNotReady() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		#expect(queue.pendingCount == 2)
	}

	@Test("markReady returns all pending URLs")
	func markReady_returnsAllPendingURLs() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		let pending = queue.markReady()

		#expect(pending == [testURL, anotherURL])
		#expect(queue.pendingCount == 0)
	}

	@Test("markReady is idempotent — second call returns empty array")
	func markReady_isIdempotent() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)

		let first = queue.markReady()
		let second = queue.markReady()

		#expect(first == [testURL])
		#expect(second.isEmpty)
	}

	@Test("After markReady, new URLs pass through immediately")
	func afterMarkReady_newURLsPassThrough() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = queue.markReady()

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
		#expect(queue.pendingCount == 0)
	}

	@Test("Queue starts not ready")
	func queue_startsNotReady() {
		let queue = DeepLinkReadinessQueue()

		#expect(!queue.isReady)
	}

	@Test("Queue is ready after markReady")
	func queue_isReadyAfterMarkReady() {
		let queue = DeepLinkReadinessQueue()

		_ = queue.markReady()

		#expect(queue.isReady)
	}

	@Test("Empty queue markReady returns empty array")
	func emptyQueue_markReadyReturnsEmpty() {
		let queue = DeepLinkReadinessQueue()

		let pending = queue.markReady()

		#expect(pending.isEmpty)
	}
}
