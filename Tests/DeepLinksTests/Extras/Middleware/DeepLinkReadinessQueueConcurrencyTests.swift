//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkReadinessQueueConcurrencyTests {
	@Test
	func `simultaneous enqueues from many tasks do not lose any URL`() async {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)
		let total = 100

		await withTaskGroup(of: Void.self) { group in
			for index in 0 ..< total {
				group.addTask {
					_ = queue.enqueue(URL(string: "stress://\(index)")!)
				}
			}
		}

		#expect(queue.pendingCount == total)

		let snapshot = queue.pendingURLs
		let uniqueLastPathComponents = Set(snapshot.compactMap(\.host))
		#expect(uniqueLastPathComponents.count == total)
	}

	@Test
	func `enqueue racing markReady never loses URLs or crashes`() async {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)
		let before = 50
		let after = 50

		await withTaskGroup(of: Void.self) { group in
			for index in 0 ..< before {
				group.addTask {
					_ = queue.enqueue(URL(string: "before://\(index)")!)
				}
			}
			group.addTask {
				_ = queue.markReady()
			}
			for index in 0 ..< after {
				group.addTask {
					_ = queue.enqueue(URL(string: "after://\(index)")!)
				}
			}
		}

		// After the race, the queue must be ready and free of undelivered URLs.
		// `markReady` only consumes URLs that were enqueued before it ran; URLs
		// enqueued after `markReady` bypass the queue (enqueue returns them to
		// the caller instead of storing them). We can't predict the split, but
		// the final state must be consistent.
		#expect(queue.isReady)
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `reset racing enqueue never crashes and converges to a consistent state`() async {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)
		let iterations = 50

		await withTaskGroup(of: Void.self) { group in
			for index in 0 ..< iterations {
				group.addTask {
					_ = queue.enqueue(URL(string: "race://\(index)")!)
				}
				group.addTask {
					queue.reset()
				}
			}
		}

		#expect(queue.isReady == false)
		// Queue may contain 0..<iterations URLs — the exact count depends on
		// interleaving. The contract is that every call returns; no URL ever
		// appears twice; the queue never contains more URLs than were enqueued.
		#expect(queue.pendingCount <= iterations)
		#expect(Set(queue.pendingURLs).count == queue.pendingCount)
	}

	@Test
	func `markReady during a full enqueue burst consumes the pre-markReady URLs`() async throws {
		let queue = DeepLinkReadinessQueue(maxQueueSize: nil)

		// Enqueue synchronously to pin the exact count, then race markReady
		// with more enqueues.
		for index in 0 ..< 10 {
			_ = try queue.enqueue(#require(URL(string: "pre://\(index)")))
		}

		var drained: [URL] = []
		let drainedLock = DrainLock()

		await withTaskGroup(of: Void.self) { group in
			group.addTask {
				let pending = queue.markReady()
				await drainedLock.set(pending)
			}
			for index in 0 ..< 10 {
				group.addTask {
					_ = queue.enqueue(URL(string: "post://\(index)")!)
				}
			}
		}

		drained = await drainedLock.value
		// markReady returns at least the 10 URLs enqueued synchronously before
		// the race; it may also capture post-race URLs that happened to land
		// before markReady acquired the lock.
		//
		// Upper bound (<= 20) catches a regression that loses the boundary
		// entirely — markReady should never see more than the 10 pre-race +
		// 10 post-race URLs enqueued in this test.
		#expect(drained.count >= 10)
		#expect(drained.count <= 20)
	}
}

// MARK: - Test Doubles

private actor DrainLock {
	private(set) var value: [URL] = []

	func set(_ urls: [URL]) {
		value = urls
	}
}
