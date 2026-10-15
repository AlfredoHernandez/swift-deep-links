//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// A delegate that collects all coordinator lifecycle events for inspection.
///
/// `CollectingDelegate` records every lifecycle event from the deep link coordinator,
/// allowing tests to verify that the correct sequence of delegate callbacks occur.
/// This delegate must be used on the main thread as it is isolated to the main actor.
///
/// ## Overview
///
/// Create a `CollectingDelegate`, attach it to your coordinator, and inspect the recorded events:
///
///     let delegate = CollectingDelegate<AppRoute>()
///     let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///         .routing(routing)
///         .handler(handler)
///         .delegate(delegate)
///         .build()
///
///     await coordinator.handle(url: someURL)
///
///     #expect(delegate.willProcessURLs.count == 1)
///     #expect(delegate.processedEvents.first?.result.wasSuccessful == true)
///
/// ## Verifying Complete Event Flow
///
/// Track the full lifecycle of URL processing:
///
///     let delegate = CollectingDelegate<AppRoute>()
///     let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///         .routing(routing)
///         .handler(handler)
///         .delegate(delegate)
///         .build()
///
///     let url = URL(string: "app://home")!
///     await coordinator.handle(url: url)
///
///     // Verify pre-processing
///     #expect(delegate.willProcessURLs.contains(url))
///
///     // Verify successful processing
///     if let event = delegate.processedEvents.first {
///         #expect(event.url == url)
///         #expect(event.result.wasSuccessful)
///     }
///
/// - Note: This delegate is `@MainActor` isolated; all methods must be called from the main thread.
/// - SeeAlso: `DeepLinkCoordinatorDelegate`
@MainActor
public final class CollectingDelegate<Route: DeepLinkRoute>: DeepLinkCoordinatorDelegate {
	/// An event captured when the coordinator finishes successfully processing a URL.
	///
	/// Represents the result of a complete deep link processing operation.
	public struct ProcessedEvent: Sendable {
		/// The URL that was processed.
		public let url: URL

		/// The result of processing the deep link.
		public let result: DeepLinkResult<Route>
	}

	/// An event captured when the coordinator fails to process a URL.
	///
	/// Represents an error that occurred during deep link processing.
	public struct FailedEvent {
		/// The URL that failed to process.
		public let url: URL

		/// The error that occurred during processing.
		public let error: Error
	}

	/// URLs passed to `willProcess(_:)`, in order.
	///
	/// Contains all URLs before they are processed by the coordinator.
	public private(set) var willProcessURLs: [URL] = []

	/// Events from `didProcess(_:result:)`, in order.
	///
	/// Contains successful processing results with their associated URLs.
	public private(set) var processedEvents: [ProcessedEvent] = []

	/// Events from `didFailProcessing(_:error:)`, in order.
	///
	/// Contains failures with their associated URLs and errors.
	public private(set) var failedEvents: [FailedEvent] = []

	/// Initializes a new collecting delegate with no recorded events.
	public init() {}

	/// Appends `url` to ``willProcessURLs``.
	public func coordinator(_: DeepLinkCoordinator<Route>, willProcess url: URL) {
		willProcessURLs.append(url)
	}

	/// Appends the URL and result to ``processedEvents``, including links
	/// middleware stopped and links whose handler failed.
	public func coordinator(_: DeepLinkCoordinator<Route>, didProcess url: URL, result: DeepLinkResult<Route>) {
		processedEvents.append(ProcessedEvent(url: url, result: result))
	}

	/// Appends the URL and error to ``failedEvents``: links that middleware or routing rejected.
	public func coordinator(_: DeepLinkCoordinator<Route>, didFailProcessing url: URL, error: Error) {
		failedEvents.append(FailedEvent(url: url, error: error))
	}
}
