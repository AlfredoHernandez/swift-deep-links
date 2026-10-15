//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Default implementation using UserDefaults for persistence.
///
/// This actor provides thread-safe access to UserDefaults for rate limit data persistence.
/// All operations are serialized through actor isolation, preventing data races.
///
/// Timestamps older than the retention are pruned during `loadRequests()` to
/// prevent unbounded growth. The retention is `maxAge`, raised to the longest
/// window a ``RateLimitMiddleware`` has used with this instance, so a long
/// window never forgets requests.
///
/// The stored count is **global per install**: every link, from any source,
/// spends the same budget, and the user (or any code in the app) can edit or
/// clear it in `UserDefaults`. Use separate keys for separate budgets.
public actor UserDefaultsRateLimitPersistence: RateLimitPersistence {
	private let userDefaults: UserDefaults
	private let key: String
	private var retention: TimeInterval
	private let dateProvider: @Sendable () -> Date

	/// Creates a new UserDefaults-based persistence.
	///
	/// - Parameters:
	///   - userDefaults: UserDefaults instance to use (defaults to .standard)
	///   - key: Key for storing data in UserDefaults (defaults to "deeplink.ratelimit.requests")
	///   - maxAge: Minimum age in seconds before stored timestamps are removed during
	///     `loadRequests()`. A longer rate-limit window raises it. Defaults to 3600 (1 hour).
	///   - dateProvider: Closure that provides the current date (defaults to `Date.init`).
	///     Useful for testing with controlled time.
	public init(
		userDefaults: UserDefaults = .standard,
		key: String = "deeplink.ratelimit.requests",
		maxAge: TimeInterval = 3600,
		dateProvider: @escaping @Sendable () -> Date = Date.init,
	) {
		self.userDefaults = userDefaults
		self.key = key
		retention = maxAge
		self.dateProvider = dateProvider
	}

	public func loadRequests() -> [TimeInterval] {
		guard let data = userDefaults.data(forKey: key),
		      let timestamps = try? JSONDecoder().decode([TimeInterval].self, from: data)
		else {
			return []
		}
		let cutoff = dateProvider().timeIntervalSince1970 - retention
		let pruned = timestamps.filter { $0 > cutoff }
		if pruned.count != timestamps.count {
			persistTimestamps(pruned)
		}
		return pruned
	}

	public func saveRequests(_ timestamps: [TimeInterval]) {
		persistTimestamps(timestamps)
	}

	public func clearRequests() {
		userDefaults.removeObject(forKey: key)
	}

	/// Loads the pruned timestamps, applies `mutation` and stores the result
	/// when it changed, all in one actor-isolated step.
	///
	/// - Parameter mutation: Reads and changes the timestamps; its result is returned.
	/// - Returns: The value `mutation` returned.
	public func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) -> Output {
		let loaded = loadRequests()
		var timestamps = loaded
		let result = mutation(&timestamps)
		if timestamps != loaded {
			persistTimestamps(timestamps)
		}
		return result
	}

	/// Raises the retention to at least `window`, then runs ``mutateRequests(_:)``.
	public func mutateRequests<Output: Sendable>(
		retaining window: TimeInterval,
		_ mutation: @Sendable (inout [TimeInterval]) -> Output,
	) async -> Output {
		if window > retention {
			retention = window
		}
		return mutateRequests(mutation)
	}

	private func persistTimestamps(_ timestamps: [TimeInterval]) {
		if let data = try? JSONEncoder().encode(timestamps) {
			userDefaults.set(data, forKey: key)
		}
	}
}
