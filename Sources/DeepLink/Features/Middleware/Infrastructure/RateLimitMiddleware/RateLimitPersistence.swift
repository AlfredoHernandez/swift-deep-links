//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for persisting rate limit data.
///
/// This protocol allows different storage mechanisms to be used for rate limiting,
/// making the middleware more flexible and testable.
///
/// All methods are async to support actor-based implementations for thread safety.
public protocol RateLimitPersistence: Sendable {
    /// Loads stored request timestamps.
    ///
    /// - Returns: Array of timestamps representing when requests were made
    func loadRequests() async -> [TimeInterval]

    /// Saves request timestamps.
    ///
    /// - Parameter timestamps: Array of timestamps to store
    func saveRequests(_ timestamps: [TimeInterval]) /// Clears all stored request data.
        async

    func clearRequests() async
}

/// Default implementation using UserDefaults for persistence.
///
/// This actor provides thread-safe access to UserDefaults for rate limit data persistence.
/// All operations are serialized through actor isolation, preventing data races.
public actor UserDefaultsRateLimitPersistence: RateLimitPersistence {
    private let userDefaults: UserDefaults
    private let key: String

    /// Creates a new UserDefaults-based persistence.
    ///
    /// - Parameters:
    ///   - userDefaults: UserDefaults instance to use (defaults to .standard)
    ///   - key: Key for storing data in UserDefaults (defaults to "deeplink.ratelimit.requests")
    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "deeplink.ratelimit.requests",
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public func loadRequests() -> [TimeInterval] {
        guard let data = userDefaults.data(forKey: key),
              let timestamps = try? JSONDecoder().decode([TimeInterval].self, from: data)
        else {
            return []
        }
        return timestamps
    }

    public func saveRequests(_ timestamps: [TimeInterval]) {
        if let data = try? JSONEncoder().encode(timestamps) {
            userDefaults.set(data, forKey: key)
        }
    }

    public func clearRequests() {
        userDefaults.removeObject(forKey: key)
    }
}
