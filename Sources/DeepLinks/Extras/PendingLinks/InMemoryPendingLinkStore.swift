//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
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

	public func save(_ url: URL) {
		links = policy.inserting(url, at: now, into: links)
	}

	public func takeAll() -> [URL] {
		defer { links.removeAll() }
		return policy.unexpired(links, at: now).map(\.url)
	}

	public func removeAll() {
		links.removeAll()
	}

	private var now: TimeInterval {
		dateProvider().timeIntervalSince1970
	}
}
