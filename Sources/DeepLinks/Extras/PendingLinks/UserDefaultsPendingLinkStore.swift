//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A ``PendingLinkStore`` persisted in `UserDefaults`, so a protected link
/// survives the app being terminated during sign-in.
///
/// Each entry stores only the URL and the time it was saved, as JSON under
/// `key`. `UserDefaults` is not encrypted: a link whose query carries a
/// secret (a password-reset token, a one-time code) is written to disk in
/// plain text. Use ``InMemoryPendingLinkStore`` for such links, or keep
/// them out of the protected set.
public actor UserDefaultsPendingLinkStore: PendingLinkStore {
	private let userDefaults: UserDefaults
	private let key: String
	private let policy: PendingLinkPolicy
	private let dateProvider: @Sendable () -> Date

	/// Creates a store over `userDefaults`.
	///
	/// - Parameters:
	///   - userDefaults: The defaults database. Defaults to `.standard`.
	///   - key: The key holding the pending links.
	///   - maxCount: Maximum number of pending links; the oldest is dropped
	///     beyond it. Clamped to at least `1`.
	///   - expiry: Seconds after which a pending link is discarded. Defaults
	///     to five minutes; zero, negative and NaN values expire links immediately.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		userDefaults: UserDefaults = .standard,
		key: String = "deeplink.pending.links",
		maxCount: Int = 1,
		expiry: TimeInterval = 300,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.userDefaults = userDefaults
		self.key = key
		policy = PendingLinkPolicy(maxCount: maxCount, expiry: expiry)
		self.dateProvider = dateProvider
	}

	public func save(_ url: URL) {
		persist(policy.inserting(url, at: now, into: storedLinks()))
	}

	public func takeAll() -> [URL] {
		defer { removeAll() }
		return policy.unexpired(storedLinks(), at: now).map(\.url)
	}

	public func removeAll() {
		userDefaults.removeObject(forKey: key)
	}

	private var now: TimeInterval {
		dateProvider().timeIntervalSince1970
	}

	private func storedLinks() -> [PendingLink] {
		guard let data = userDefaults.data(forKey: key) else { return [] }
		return (try? JSONDecoder().decode([PendingLink].self, from: data)) ?? []
	}

	private func persist(_ links: [PendingLink]) {
		guard let data = try? JSONEncoder().encode(links) else { return }
		userDefaults.set(data, forKey: key)
	}
}
