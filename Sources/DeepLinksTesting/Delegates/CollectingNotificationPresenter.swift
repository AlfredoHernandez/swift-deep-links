//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(UserNotifications) && !os(tvOS)

import DeepLinks
import Foundation

/// A ``DeepLinkNotificationPresenter`` that records every `present(...)` call
/// for later inspection.
///
/// `CollectingNotificationPresenter` swaps in for
/// ``DefaultDeepLinkNotificationPresenter`` in unit tests so the notification
/// payloads can be asserted against without actually hitting
/// `UNUserNotificationCenter`.
///
/// ## Overview
///
///     let presenter = CollectingNotificationPresenter()
///     let delegate = DeepLinkNotificationDelegate<AppRoute>(
///         showErrorNotifications: true,
///         presenter: presenter,
///     )
///     // ... drive the delegate ...
///     let invocations = await presenter.waitFor(count: 1)
///     #expect(invocations.first?.kind == .failure)
///
/// ## Awaiting events
///
/// ``waitFor(count:)`` provides a deterministic fence: it suspends until at
/// least `count` invocations have been recorded, then resumes. This avoids the
/// busy-loop / wall-clock polling pattern that flakes under parallel test
/// execution.
///
/// - Note: This type is an `actor`, so every access crosses the actor
///   boundary — assertions on its state must be awaited.
public actor CollectingNotificationPresenter: DeepLinkNotificationPresenter {
	/// A single captured invocation of ``present(kind:title:body:identifier:)``.
	public struct Invocation: Sendable, Equatable {
		/// The lifecycle severity the delegate tagged the invocation with.
		public let kind: DeepLinkNotificationKind
		/// The notification headline.
		public let title: String
		/// The notification body text.
		public let body: String
		/// The unique identifier the delegate constructed for deduplication.
		public let identifier: String
	}

	private var invocations: [Invocation] = []
	private var pendingAwaiter: (count: Int, continuation: CheckedContinuation<[Invocation], Never>)?

	/// Creates a new presenter with no recorded invocations.
	public init() {}

	/// Every invocation received so far, in the order they arrived.
	///
	/// Callers who need the count should read `recordedInvocations.count` —
	/// the type matches the shape of ``DeepLinksTesting/CollectingHandler``
	/// and ``DeepLinksTesting/CollectingDelegate``, which expose only the
	/// raw arrays.
	public var recordedInvocations: [Invocation] {
		invocations
	}

	/// Records the invocation and resumes a waiting
	/// ``waitFor(count:)`` once enough have arrived; never throws.
	public func present(kind: DeepLinkNotificationKind, title: String, body: String, identifier: String) async throws {
		invocations.append(Invocation(kind: kind, title: title, body: body, identifier: identifier))
		if let awaiter = pendingAwaiter, invocations.count >= awaiter.count {
			let snapshot = invocations
			pendingAwaiter = nil
			awaiter.continuation.resume(returning: snapshot)
		}
	}

	/// Suspends until at least `count` invocations have been recorded, then
	/// returns the accumulated snapshot.
	///
	/// Use this as a deterministic fence in place of polling or sleeping.
	/// Only one awaiter is supported at a time; a second concurrent call
	/// trips a `precondition` so the misuse fails loudly instead of silently
	/// stranding the first continuation.
	///
	/// - Parameter count: The number of invocations to wait for.
	/// - Returns: The invocations recorded so far, once the threshold is met.
	public func waitFor(count: Int) async -> [Invocation] {
		if invocations.count >= count {
			return invocations
		}
		return await withCheckedContinuation { continuation in
			precondition(
				pendingAwaiter == nil,
				"CollectingNotificationPresenter supports a single concurrent awaiter",
			)
			pendingAwaiter = (count, continuation)
		}
	}
}

#endif
