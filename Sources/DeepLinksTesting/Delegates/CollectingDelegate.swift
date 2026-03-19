//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A delegate that collects all coordinator lifecycle events for inspection.
///
/// ```swift
/// let delegate = CollectingDelegate()
/// let coordinator = try await DeepLinkCoordinatorBuilder<AppRoute>()
///     .routing(routing)
///     .handler(handler)
///     .delegate(delegate)
///     .build()
///
/// await coordinator.handle(url: someURL)
///
/// #expect(delegate.willProcessURLs.count == 1)
/// #expect(delegate.processedEvents.first?.result.wasSuccessful == true)
/// ```
@MainActor
public final class CollectingDelegate: DeepLinkCoordinatorDelegate {
	/// An event captured when the coordinator finishes processing a URL.
	public struct ProcessedEvent: Sendable {
		public let url: URL
		public let result: DeepLinkResultProtocol
	}

	/// An event captured when the coordinator fails to process a URL.
	public struct FailedEvent {
		public let url: URL
		public let error: Error
	}

	/// URLs passed to `willProcess`, in order.
	public private(set) var willProcessURLs: [URL] = []

	/// Events from `didProcess`, in order.
	public private(set) var processedEvents: [ProcessedEvent] = []

	/// Events from `didFailProcessing`, in order.
	public private(set) var failedEvents: [FailedEvent] = []

	public init() {}

	public func coordinator(_: AnyObject, willProcess url: URL) {
		willProcessURLs.append(url)
	}

	public func coordinator(_: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol) {
		processedEvents.append(ProcessedEvent(url: url, result: result))
	}

	public func coordinator(_: AnyObject, didFailProcessing url: URL, error: Error) {
		failedEvents.append(FailedEvent(url: url, error: error))
	}
}
