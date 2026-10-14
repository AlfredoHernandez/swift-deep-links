//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// A clock that only moves when the test moves it.
///
/// Pass ``dateProvider`` wherever the library accepts a
/// `@Sendable () -> Date` (rate limiting, replay protection, pending-link
/// stores) and call ``advance(by:)`` instead of sleeping:
///
///     let clock = ManualDateProvider()
///     let middleware = RateLimitMiddleware(
///         persistence: InMemoryRateLimitPersistence(),
///         strategy: .tokenBucket(capacity: 2, refillRate: 1),
///         dateProvider: clock.dateProvider
///     )
///
///     _ = try await middleware.intercept(url)
///     _ = try await middleware.intercept(url)
///     clock.advance(by: 1)  // one token refilled
///
/// - Thread Safety: Reads and writes are lock-protected; safe from any task.
public final class ManualDateProvider: Sendable {
	/// The instant a provider starts at when none is given: 2023-11-14T22:13:20Z.
	public static let defaultStart = Date(timeIntervalSince1970: 1_700_000_000)

	private let current: OSAllocatedUnfairLock<Date>

	/// Creates a clock frozen at `now`.
	///
	/// - Parameter now: The starting instant. Defaults to ``defaultStart``.
	public init(now: Date = ManualDateProvider.defaultStart) {
		current = OSAllocatedUnfairLock(initialState: now)
	}

	/// The current instant.
	public var now: Date {
		get { current.withLock { $0 } }
		set { current.withLock { $0 = newValue } }
	}

	/// A closure returning the current instant, for APIs taking a `dateProvider`.
	/// It reads the clock on every call, so later ``advance(by:)`` calls are visible.
	public var dateProvider: @Sendable () -> Date {
		{ [current] in current.withLock { $0 } }
	}

	/// Moves the clock by `seconds`; negative values move it backwards.
	public func advance(by seconds: TimeInterval) {
		current.withLock { $0 = $0.addingTimeInterval(seconds) }
	}
}
