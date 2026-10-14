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
/// store nothing but each URL, the ``DeepLinkContext`` it arrived with
/// (source, source application, scene) and the time it was saved, so a
/// resumed link reaches the handler with its original context.
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

	/// Saves `request` as the newest pending link, keeping its context.
	/// The default saves only the URL, so a store implementing only
	/// ``save(_:)-(URL)`` resumes links with ``DeepLinkContext/unknown``.
	func save(_ request: DeepLinkRequest) async

	/// Returns every unexpired pending link with its context, oldest first,
	/// and empties the store. The default wraps ``takeAll()``.
	func takeAllRequests() async -> [DeepLinkRequest]
}

public extension PendingLinkStore {
	func save(_ request: DeepLinkRequest) async {
		await save(request.url)
	}

	func takeAllRequests() async -> [DeepLinkRequest] {
		await takeAll().map { DeepLinkRequest(url: $0) }
	}
}

/// A pending URL, its context and the moment it was saved; the only data a store keeps.
struct PendingLink: Codable, Equatable {
	let url: URL
	let savedAt: TimeInterval
	var context: StoredContext?

	var request: DeepLinkRequest {
		DeepLinkRequest(url: url, context: context?.context ?? .unknown)
	}
}

/// The persisted form of a ``DeepLinkContext``. Versioned; an unknown source
/// decodes as ``DeepLinkContext/Source/unknown``. The signature-verified flag
/// is never stored, so a tampered store cannot vouch for a link.
struct StoredContext: Codable, Equatable {
	var version = 1
	var source: String
	var sourceApplication: String?
	var sceneID: String?

	init(_ context: DeepLinkContext) {
		source = context.source.rawValue
		sourceApplication = context.sourceApplication
		sceneID = context.sceneID
	}

	var context: DeepLinkContext {
		DeepLinkContext(
			source: DeepLinkContext.Source(rawValue: source) ?? .unknown,
			sourceApplication: sourceApplication,
			sceneID: sceneID,
		)
	}
}

/// The bounded, expiring list shared by the built-in stores.
struct PendingLinkPolicy: Sendable {
	let maxCount: Int
	let expiry: TimeInterval

	init(maxCount: Int, expiry: TimeInterval) {
		self.maxCount = max(maxCount, 1)
		self.expiry = expiry.isNaN ? 0 : max(expiry, 0)
	}

	func inserting(_ request: DeepLinkRequest, at now: TimeInterval, into links: [PendingLink]) -> [PendingLink] {
		let others = unexpired(links, at: now).filter { $0.url != request.url }
		let link = PendingLink(url: request.url, savedAt: now, context: StoredContext(request.context))
		return Array((others + [link]).suffix(maxCount))
	}

	func unexpired(_ links: [PendingLink], at now: TimeInterval) -> [PendingLink] {
		links.filter { (0 ..< expiry).contains(now - $0.savedAt) }
	}
}
