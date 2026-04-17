//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct ReadinessMiddlewareTests {
	private let testURL = URL(string: "myapp://test")!
	private let anotherURL = URL(string: "myapp://other")!

	// MARK: - Queue Tests

	@Test
	func `When ready, URL passes through immediately`() async throws {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()
		let sut = ReadinessMiddleware(queue: queue)

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `When not ready, URL is queued and nil is returned`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		let result = try await sut.intercept(testURL)

		#expect(result == nil)
		#expect(queue.pendingCount == 1)
	}

	@Test
	func `Multiple URLs are queued when not ready`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		#expect(queue.pendingCount == 2)
	}

	@Test
	func `markReady returns all pending URLs`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)
		_ = try await sut.intercept(anotherURL)

		let pending = queue.markReady()

		#expect(pending == [testURL, anotherURL])
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `markReady is idempotent — second call returns empty array`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = try await sut.intercept(testURL)

		let first = queue.markReady()
		let second = queue.markReady()

		#expect(first == [testURL])
		#expect(second.isEmpty)
	}

	@Test
	func `After markReady, new URLs pass through immediately`() async throws {
		let queue = DeepLinkReadinessQueue()
		let sut = ReadinessMiddleware(queue: queue)

		_ = queue.markReady()

		let result = try await sut.intercept(testURL)

		#expect(result == testURL)
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `Queue starts not ready`() {
		let queue = DeepLinkReadinessQueue()

		#expect(!queue.isReady)
	}

	@Test
	func `Queue is ready after markReady`() {
		let queue = DeepLinkReadinessQueue()

		_ = queue.markReady()

		#expect(queue.isReady)
	}

	@Test
	func `Empty queue markReady returns empty array`() {
		let queue = DeepLinkReadinessQueue()

		let pending = queue.markReady()

		#expect(pending.isEmpty)
	}

	// MARK: - maxQueueSize Tests

	@Test
	func `maxQueueSize drops oldest URL when queue is full`() throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: 2)
		let thirdURL = try #require(URL(string: "myapp://third"))

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)
		_ = queue.enqueue(thirdURL)

		#expect(queue.pendingCount == 2)

		let pending = queue.markReady()
		#expect(pending == [anotherURL, thirdURL])
	}

	@Test
	func `maxQueueSize of 1 keeps only the latest URL`() {
		let queue = DeepLinkReadinessQueue(maxQueueSize: 1)

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)

		let pending = queue.markReady()
		#expect(pending == [anotherURL])
	}

	@Test
	func `maxQueueSize zero or negative is clamped to 1`() {
		let zeroQueue = DeepLinkReadinessQueue(maxQueueSize: 0)
		let negativeQueue = DeepLinkReadinessQueue(maxQueueSize: -5)

		_ = zeroQueue.enqueue(testURL)
		_ = zeroQueue.enqueue(anotherURL)
		#expect(zeroQueue.pendingCount == 1)

		_ = negativeQueue.enqueue(testURL)
		_ = negativeQueue.enqueue(anotherURL)
		#expect(negativeQueue.pendingCount == 1)
	}

	@Test
	func `nil maxQueueSize allows unlimited URLs`() throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)

		for i in 0 ..< 100 {
			_ = try queue.enqueue(#require(URL(string: "myapp://item/\(i)")))
		}

		#expect(queue.pendingCount == 100)
	}

	// MARK: - Reset Tests

	@Test
	func `reset returns queue to not-ready state`() {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()
		#expect(queue.isReady)

		queue.reset()

		#expect(!queue.isReady)
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `reset discards pending URLs`() {
		let queue = DeepLinkReadinessQueue()

		_ = queue.enqueue(testURL)
		_ = queue.enqueue(anotherURL)
		#expect(queue.pendingCount == 2)

		queue.reset()

		#expect(queue.pendingCount == 0)
		#expect(queue.markReady().isEmpty)
	}

	@Test
	func `After reset, new URLs are queued again`() {
		let queue = DeepLinkReadinessQueue()
		_ = queue.markReady()

		queue.reset()

		let result = queue.enqueue(testURL)

		#expect(result == nil)
		#expect(queue.pendingCount == 1)
	}
}
