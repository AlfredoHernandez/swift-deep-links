//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for persisting rate limit data.
///
/// This protocol allows different storage mechanisms to be used for rate limiting,
/// making the middleware more flexible and testable.
///
/// All methods are async to support actor-based implementations for thread safety.
///
/// ## Atomicity
///
/// ``RateLimitMiddleware`` reads and records requests only through
/// ``mutateRequests(_:)``, which must run the read-modify-write without
/// suspending, so separate middleware instances sharing one persistence
/// still admit exactly their limit. An actor satisfies this by calling the
/// closure synchronously on its isolated state:
///
/// ```swift
/// actor KeychainRateLimitPersistence: RateLimitPersistence {
///     private var timestamps: [TimeInterval] = []
///
///     func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) -> Output {
///         let result = mutation(&timestamps)
///         // persist `timestamps` synchronously here
///         return result
///     }
///     // loadRequests(), saveRequests(_:), clearRequests() …
/// }
/// ```
public protocol RateLimitPersistence: Sendable {
	/// Loads stored request timestamps.
	///
	/// - Returns: Array of timestamps representing when requests were made
	func loadRequests() async -> [TimeInterval]

	/// Saves request timestamps.
	///
	/// - Parameter timestamps: Array of timestamps to store
	func saveRequests(_ timestamps: [TimeInterval]) async

	/// Clears all stored request data.
	func clearRequests() async

	/// Atomically reads the stored timestamps, lets `mutation` change them,
	/// and stores the changed timestamps.
	///
	/// No other call on this persistence may observe or change the
	/// timestamps between the read and the write; do not suspend inside.
	///
	/// - Parameter mutation: Reads and changes the timestamps. Leave them
	///   unchanged to record nothing.
	/// - Returns: The value `mutation` returned.
	func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) async -> Output
}
