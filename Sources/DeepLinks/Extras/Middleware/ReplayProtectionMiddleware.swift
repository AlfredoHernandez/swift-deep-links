//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// Middleware that suppresses the same deep link arriving again within a
/// short window.
///
/// Guards against **accidental** double delivery: double taps, a link
/// delivered through two entry points (`onOpenURL` and `NSUserActivity`),
/// and pages that fire the same link repeatedly. It is not a security
/// control against deliberate replay: its memory is per process, short-lived
/// and bounded, so an attacker can wait out the window or evict entries. Make
/// sensitive links single-use with ``SignedLinkMiddleware`` and a ``NonceStore``. A link is a replay when its key (see ``ReplayKeyStrategy``)
/// was first seen less than `window` seconds earlier. Replays do not extend
/// the window, so a key is admitted at most once per window.
///
/// Memory is bounded: expired keys are pruned on every link and, when
/// `maxEntries` keys are live, the oldest is evicted to make room. An evicted
/// key can be admitted again before its window ends; size `maxEntries` above
/// the number of distinct links you expect inside one window.
///
/// The record is kept in memory only and is checked and updated atomically,
/// so concurrent identical links admit exactly one. If the clock moves
/// backwards, earlier entries count as expired.
///
/// ## Placement
///
/// A key is recorded when the link passes this middleware, even if later
/// middleware rejects it. Place it after ``SecurityMiddleware``, the rate
/// limiter (so a flood of distinct links cannot evict entries cheaply) and
/// ``AuthenticationMiddleware``: placed before authentication, a protected
/// link resumed with ``DeepLinkCoordinator/resumePendingLinks(from:)``
/// inside the window would be dropped as a replay.
///
/// ## Example
///
/// ```swift
/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
///     .parser(parser)
///     .handler(handler)
///     .middleware(
///         .security(allowedSchemes: ["myapp"], strategy: .hardened),
///         .replayProtection(window: 2, ignoredQueryKeys: ["utm_source"])
///     )
///     .build()
/// ```
public final class ReplayProtectionMiddleware: DeepLinkMiddleware {
	/// What happens to a replayed link.
	public enum Response: Sendable {
		/// Stop the chain without an error; the result reports
		/// ``DeepLinkResult/wasStoppedByMiddleware``.
		case drop

		/// Throw ``DeepLinkError/securityViolation(_:)`` with the reason
		/// `"Replayed deep link"`.
		case reject
	}

	fileprivate struct State {
		var firstSeen: [String: Date] = [:]
		var arrivalOrder: [String] = []
	}

	private let window: TimeInterval
	private let maxEntries: Int
	private let keyStrategy: ReplayKeyStrategy
	private let ignoredQueryKeys: Set<String>
	private let response: Response
	private let dateProvider: @Sendable () -> Date
	private let state = OSAllocatedUnfairLock(initialState: State())

	/// Creates a replay protection middleware.
	///
	/// - Parameters:
	///   - window: Seconds during which a repeated key is a replay. Zero,
	///     negative and NaN values disable protection.
	///   - maxEntries: Maximum number of keys remembered; clamped to at least `1`.
	///   - key: Which parts of the URL identify a link. Defaults to ``ReplayKeyStrategy/url``.
	///   - ignoredQueryKeys: Query parameter names (case-sensitive) removed
	///     before the key is computed, such as tracking parameters or timestamps.
	///   - response: Whether a replay is dropped silently or rejected with an error.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		window: TimeInterval = 2,
		maxEntries: Int = 100,
		key: ReplayKeyStrategy = .url,
		ignoredQueryKeys: Set<String> = [],
		response: Response = .drop,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.window = window.isNaN ? 0 : window
		self.maxEntries = max(maxEntries, 1)
		keyStrategy = key
		self.ignoredQueryKeys = ignoredQueryKeys
		self.response = response
		self.dateProvider = dateProvider
	}

	/// Passes the request through unless it replays a link seen within the window.
	///
	/// - Parameter request: The deep link to check.
	/// - Returns: `request` unchanged, or `nil` for a replay with the ``Response/drop`` response.
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` for a replay with the
	///   ``Response/reject`` response.
	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard window > 0, let key = keyStrategy.key(for: removingIgnoredQueryKeys(from: request.url)) else {
			return request
		}

		guard isReplay(key, at: dateProvider()) else { return request }

		switch response {
		case .drop:
			return nil

		case .reject:
			throw DeepLinkError.securityViolation("Replayed deep link")
		}
	}

	var trackedKeyCount: Int {
		state.withLock { $0.firstSeen.count }
	}
}

// MARK: - Replay Record

private extension ReplayProtectionMiddleware {
	func isReplay(_ key: String, at now: Date) -> Bool {
		state.withLock { state in
			pruneExpired(&state, at: now)

			if state.firstSeen[key] != nil {
				return true
			}

			if state.arrivalOrder.count >= maxEntries {
				state.firstSeen[state.arrivalOrder.removeFirst()] = nil
			}
			state.firstSeen[key] = now
			state.arrivalOrder.append(key)
			return false
		}
	}

	func pruneExpired(_ state: inout State, at now: Date) {
		state.arrivalOrder.removeAll { key in
			guard let seenAt = state.firstSeen[key], (0 ..< window).contains(now.timeIntervalSince(seenAt)) else {
				state.firstSeen[key] = nil
				return true
			}
			return false
		}
	}

	func removingIgnoredQueryKeys(from url: URL) -> URL {
		guard !ignoredQueryKeys.isEmpty,
		      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      let items = components.percentEncodedQueryItems
		else {
			return url
		}

		let kept = items.filter { item in
			!ignoredQueryKeys.contains(item.name.removingPercentEncoding ?? item.name)
		}
		components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
		return components.url ?? url
	}
}
