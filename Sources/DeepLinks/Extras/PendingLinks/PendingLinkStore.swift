//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Holds deep links that could not run yet, so they can be resumed later.
///
/// ``AuthenticationMiddleware`` saves a protected link here when the user is
/// signed out; once the user signs in, call
/// ``DeepLinkCoordinator/resumePendingLinks(from:)`` to run it again through
/// the whole middleware chain, so authentication is checked a second time.
///
/// Implementations keep at most a fixed number of links, drop links older
/// than their expiry (or saved in the future, after a clock rollback), and
/// store nothing but each URL and the time it was saved.
///
/// ## Security
///
/// Any app or web page can trigger a protected link, so a saved link may be
/// hostile, and resuming it acts with the session of whoever signs in next.
/// Only protect routes whose handlers are safe to run without a fresh user
/// action, or confirm with the user before acting; and call ``removeAll()``
/// on sign-out so one account's pending link never runs for another.
public protocol PendingLinkStore: Sendable {
	/// Saves `url` as the newest pending link. Saving a URL that is already
	/// pending moves it to the newest position instead of duplicating it.
	func save(_ url: URL) async

	/// Returns every unexpired pending link, oldest first, and empties the store.
	func takeAll() async -> [URL]

	/// Discards every pending link, for example on sign-out.
	func removeAll() async
}

/// A pending URL and the moment it was saved; the only data a store keeps.
struct PendingLink: Codable, Equatable {
	let url: URL
	let savedAt: TimeInterval
}

/// The bounded, expiring list shared by the built-in stores.
struct PendingLinkPolicy: Sendable {
	let maxCount: Int
	let expiry: TimeInterval

	init(maxCount: Int, expiry: TimeInterval) {
		self.maxCount = max(maxCount, 1)
		self.expiry = expiry.isNaN ? 0 : max(expiry, 0)
	}

	func inserting(_ url: URL, at now: TimeInterval, into links: [PendingLink]) -> [PendingLink] {
		let others = unexpired(links, at: now).filter { $0.url != url }
		return Array((others + [PendingLink(url: url, savedAt: now)]).suffix(maxCount))
	}

	func unexpired(_ links: [PendingLink], at now: TimeInterval) -> [PendingLink] {
		links.filter { (0 ..< expiry).contains(now - $0.savedAt) }
	}
}
