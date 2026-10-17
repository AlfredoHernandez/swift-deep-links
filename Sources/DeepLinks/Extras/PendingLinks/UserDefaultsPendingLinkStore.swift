//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A ``PendingLinkStore`` persisted in `UserDefaults`, so a protected link
/// survives the app being terminated during sign-in.
///
/// Each entry stores the URL, the time it was saved and the link's context
/// (source, the opening app's bundle identifier and the scene identifier,
/// never the signature-verified flag), as versioned JSON under `key`.
/// `UserDefaults` is not encrypted: a link whose query carries a secret (a
/// password-reset token, a one-time code) is written to disk in plain text,
/// and the source application reveals which app opened the link. Use
/// ``InMemoryPendingLinkStore`` for such links, or keep them out of the
/// protected set; ``removeAll()`` clears everything.
///
/// Anyone with access to the app container can edit `UserDefaults`, so the
/// stored source and source application are not trusted: resumed links come
/// back with ``DeepLinkContext/Source/unknown`` and no source application,
/// keeping only the scene identifier, which merely picks a window. Rules
/// restricting sources (`allowedSources`, ``DeepLinkMatcher/sources(_:)``) then
/// treat a resumed link as unknown; use ``InMemoryPendingLinkStore``, which
/// keeps the whole context, when such a rule must accept resumed links.
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

	/// Saves `url` with ``DeepLinkContext/unknown``; see ``save(_:)-(DeepLinkRequest)``.
	public func save(_ url: URL) async {
		await save(DeepLinkRequest(url: url))
	}

	/// The URLs of ``takeAllRequests()``: unexpired links, oldest first. The stored entry is removed afterwards.
	public func takeAll() async -> [URL] {
		await takeAllRequests().map(\.url)
	}

	/// Writes `request` as the newest link, with its context (without the
	/// signature-verified flag) and the current time, in plain text.
	///
	/// A URL already pending moves to the newest position; beyond `maxCount`
	/// the oldest link is dropped. Unreadable stored data is treated as empty
	/// and overwritten.
	public func save(_ request: DeepLinkRequest) async {
		persist(policy.inserting(request, at: now, into: storedLinks()))
	}

	/// Returns the links saved less than `expiry` seconds ago, oldest first,
	/// and removes the stored entry. Each link comes back with
	/// ``DeepLinkContext/Source/unknown`` and only its stored scene identifier,
	/// whatever source the stored data claims.
	public func takeAllRequests() async -> [DeepLinkRequest] {
		defer { removeAll() }
		return policy.unexpired(storedLinks(), at: now).map { link in
			DeepLinkRequest(url: link.url, context: DeepLinkContext(source: .unknown, sceneID: link.context?.sceneID))
		}
	}

	/// Removes the stored entry; call it on sign-out.
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
