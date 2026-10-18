//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import os

/// Fans each published result out to every live `AsyncStream` subscriber.
///
/// Each subscriber buffers at most ``bufferSize`` undelivered results and
/// drops the oldest beyond that, so a stalled consumer cannot grow memory
/// without bound. Streams finish when the broadcaster is deallocated.
final class ResultBroadcaster<Route: DeepLinkRoute>: Sendable {
	typealias Continuation = AsyncStream<DeepLinkResult<Route>>.Continuation

	static var bufferSize: Int {
		100
	}

	private let subscribers = OSAllocatedUnfairLock<[UUID: Continuation]>(initialState: [:])

	var subscriberCount: Int {
		subscribers.withLock { $0.count }
	}

	func makeStream() -> AsyncStream<DeepLinkResult<Route>> {
		let (stream, continuation) = AsyncStream<DeepLinkResult<Route>>.makeStream(bufferingPolicy: .bufferingNewest(Self.bufferSize))
		let id = UUID()
		subscribers.withLock { $0[id] = continuation }
		continuation.onTermination = { [weak self] _ in
			self?.subscribers.withLock { $0[id] = nil }
		}
		return stream
	}

	func publish(_ result: DeepLinkResult<Route>) {
		for continuation in subscribers.withLock({ Array($0.values) }) {
			continuation.yield(result)
		}
	}

	deinit {
		for continuation in subscribers.withLock({ Array($0.values) }) {
			continuation.finish()
		}
	}
}
