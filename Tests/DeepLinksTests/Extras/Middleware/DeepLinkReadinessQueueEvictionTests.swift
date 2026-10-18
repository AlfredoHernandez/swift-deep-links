//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import os
import Testing

struct DeepLinkReadinessQueueEvictionTests {
	@Test
	func `onEvict receives the oldest URL dropped by a full queue`() throws {
		let evicted = EvictionRecorder()
		let sut = DeepLinkReadinessQueue(maxQueueSize: 2, onEvict: evicted.record)
		let first = try #require(URL(string: "myapp://first"))
		let second = try #require(URL(string: "myapp://second"))
		let third = try #require(URL(string: "myapp://third"))

		_ = sut.enqueue(first)
		_ = sut.enqueue(second)
		_ = sut.enqueue(third)

		#expect(evicted.urls == [first])
		#expect(sut.pendingURLs == [second, third])
	}

	@Test
	func `onEvict is not called while the queue has room`() throws {
		let evicted = EvictionRecorder()
		let sut = DeepLinkReadinessQueue(maxQueueSize: 2, onEvict: evicted.record)

		_ = try sut.enqueue(#require(URL(string: "myapp://first")))
		_ = try sut.enqueue(#require(URL(string: "myapp://second")))

		#expect(evicted.urls.isEmpty)
	}

	@Test
	func `onEvict is not called for an unbounded queue`() throws {
		let evicted = EvictionRecorder()
		let sut = DeepLinkReadinessQueue(maxQueueSize: nil, onEvict: evicted.record)

		for index in 0 ..< 100 {
			_ = try sut.enqueue(#require(URL(string: "myapp://item/\(index)")))
		}

		#expect(evicted.urls.isEmpty)
		#expect(sut.pendingCount == 100)
	}

	@Test
	func `onEvict is not called once the queue is ready`() throws {
		let evicted = EvictionRecorder()
		let sut = DeepLinkReadinessQueue(maxQueueSize: 1, onEvict: evicted.record)
		_ = sut.markReady()

		_ = try sut.enqueue(#require(URL(string: "myapp://first")))
		_ = try sut.enqueue(#require(URL(string: "myapp://second")))

		#expect(evicted.urls.isEmpty)
	}

	@Test
	func `onEvict may read the queue without deadlocking`() throws {
		let observedCounts = OSAllocatedUnfairLock<[Int]>(initialState: [])
		let box = QueueBox()
		let sut = DeepLinkReadinessQueue(maxQueueSize: 1) { _ in
			let count = box.queue?.pendingCount ?? -1
			observedCounts.withLock { $0.append(count) }
		}
		box.queue = sut

		_ = try sut.enqueue(#require(URL(string: "myapp://first")))
		_ = try sut.enqueue(#require(URL(string: "myapp://second")))

		#expect(observedCounts.withLock { $0 } == [1])
	}
}

private final class EvictionRecorder: Sendable {
	private let state = OSAllocatedUnfairLock<[URL]>(initialState: [])

	var urls: [URL] {
		state.withLock { $0 }
	}

	var record: @Sendable (URL) -> Void {
		{ [state] url in state.withLock { $0.append(url) } }
	}
}

private final class QueueBox: Sendable {
	private let storage = OSAllocatedUnfairLock<DeepLinkReadinessQueue?>(initialState: nil)

	var queue: DeepLinkReadinessQueue? {
		get { storage.withLock { $0 } }
		set { storage.withLock { $0 = newValue } }
	}
}
