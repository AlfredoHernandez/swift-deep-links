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

	// MARK: - maxQueueSize Tests

	@Test("maxQueueSize drops oldest URL when queue is full")
	func maxQueueSize_dropsOldestWhenFull() throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: 2)
		let thirdURL = try #require(URL(string: "myapp://third"))

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)
		_ = queue.enqueue(thirdURL)

		#expect(queue.pendingCount == 2)

		let pending = queue.markReady()
		#expect(pending == [anotherURL, thirdURL])
	}

	@Test("maxQueueSize of 1 keeps only the latest URL")
	func maxQueueSize_oneKeepsLatest() {
		let queue = DeepLinkReadinessQueue(maxQueueSize: 1)

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)

		let pending = queue.markReady()
		#expect(pending == [anotherURL])
	}

	@Test("maxQueueSize zero or negative is clamped to 1")
	func maxQueueSize_zeroOrNegativeClampedToOne() {
		let zeroQueue = DeepLinkReadinessQueue(maxQueueSize: 0)
		let negativeQueue = DeepLinkReadinessQueue(maxQueueSize: -5)

		_ = zeroQueue.enqueue(testURL)
		_ = zeroQueue.enqueue(anotherURL)
		#expect(zeroQueue.pendingCount == 1)

		_ = negativeQueue.enqueue(testURL)
		_ = negativeQueue.enqueue(anotherURL)
		#expect(negativeQueue.pendingCount == 1)
	}

	@Test("nil maxQueueSize allows unlimited URLs")
	func maxQueueSize_nilAllowsUnlimited() throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)

		for i in 0 ..< 100 {
			_ = try queue.enqueue(#require(URL(string: "myapp://item/\(i)")))
		}

		#expect(queue.pendingCount == 100)
	}

	// MARK: - Reset Tests

	@Test("reset returns queue to not-ready state")
	func reset_returnsToNotReadyState() {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()
		#expect(queue.isReady)

		queue.reset()

		#expect(!queue.isReady)
		#expect(queue.pendingCount == 0)
	}

	@Test("reset discards pending URLs")
	func reset_discardsPendingURLs() {
		let queue = DeepLinkReadinessQueue()

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)
		#expect(queue.pendingCount == 2)

		queue.reset()

		#expect(queue.pendingCount == 0)
		#expect(queue.markReady().isEmpty)
	}

	@Test("After reset, new URLs are queued again")
	func reset_newURLsAreQueuedAgain() {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()

		queue.reset()

		let result = queue.enqueue(testURL)

		#expect(result == nil)
		#expect(queue.pendingCount == 1)
	}
}
