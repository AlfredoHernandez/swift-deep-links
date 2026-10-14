//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Default implementation using UserDefaults for persistence.
///
/// This actor provides thread-safe access to UserDefaults for rate limit data persistence.
/// All operations are serialized through actor isolation, preventing data races.
///
/// Expired timestamps older than `maxAge` are automatically pruned during `loadRequests()`
/// to prevent unbounded growth over time.
public actor UserDefaultsRateLimitPersistence: RateLimitPersistence {
	private let userDefaults: UserDefaults
	private let key: String
	private let maxAge: TimeInterval
	private let dateProvider: @Sendable () -> Date

	/// Creates a new UserDefaults-based persistence.
	///
	/// - Parameters:
	///   - userDefaults: UserDefaults instance to use (defaults to .standard)
	///   - key: Key for storing data in UserDefaults (defaults to "deeplink.ratelimit.requests")
	///   - maxAge: Maximum age in seconds for stored timestamps. Timestamps older than this
	///     are automatically removed during `loadRequests()`. Defaults to 3600 (1 hour).
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
		self.maxAge = maxAge
		self.dateProvider = dateProvider
	}

	public func loadRequests() -> [TimeInterval] {
		guard let data = userDefaults.data(forKey: key),
		      let timestamps = try? JSONDecoder().decode([TimeInterval].self, from: data)
		else {
			return []
		}
		let cutoff = dateProvider().timeIntervalSince1970 - maxAge
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

	private func persistTimestamps(_ timestamps: [TimeInterval]) {
		if let data = try? JSONEncoder().encode(timestamps) {
			userDefaults.set(data, forKey: key)
		}
	}
}
