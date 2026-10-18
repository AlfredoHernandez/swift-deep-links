//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// A ``PendingLinkStore`` kept in memory, lost when the app terminates.
///
/// Prefer it for links that carry secrets (tokens, codes): nothing reaches disk.
public actor InMemoryPendingLinkStore: PendingLinkStore {
	private let policy: PendingLinkPolicy
	private let dateProvider: @Sendable () -> Date
	private var links: [PendingLink] = []

	/// Creates an empty store.
	///
	/// - Parameters:
	///   - maxCount: Maximum number of pending links; the oldest is dropped
	///     beyond it. Clamped to at least `1`. Defaults to `1`, so only the
	///     latest protected link is resumed.
	///   - expiry: Seconds after which a pending link is discarded. Defaults
	///     to five minutes; zero, negative and NaN values expire links immediately.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		maxCount: Int = 1,
		expiry: TimeInterval = 300,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		policy = PendingLinkPolicy(maxCount: maxCount, expiry: expiry)
		self.dateProvider = dateProvider
	}

	/// Saves `url` with ``DeepLinkContext/unknown``; see ``save(_:)-(DeepLinkRequest)``.
	public func save(_ url: URL) async {
		await save(DeepLinkRequest(url: url))
	}

	/// The URLs of ``takeAllRequests()``: unexpired links, oldest first. The store is empty afterwards.
	public func takeAll() async -> [URL] {
		await takeAllRequests().map(\.url)
	}

	/// Saves `request` as the newest link, with its context and the current time.
	///
	/// A URL already pending moves to the newest position instead of being
	/// duplicated; beyond `maxCount` the oldest link is dropped.
	public func save(_ request: DeepLinkRequest) async {
		links = policy.inserting(request, at: now, into: links)
	}

	/// Returns the links saved less than `expiry` seconds ago, oldest first,
	/// and empties the store, expired links included.
	public func takeAllRequests() async -> [DeepLinkRequest] {
		defer { links.removeAll() }
		return policy.unexpired(links, at: now).map(\.request)
	}

	/// Discards every pending link; call it on sign-out.
	public func removeAll() {
		links.removeAll()
	}

	private var now: TimeInterval {
		dateProvider().timeIntervalSince1970
	}
}
