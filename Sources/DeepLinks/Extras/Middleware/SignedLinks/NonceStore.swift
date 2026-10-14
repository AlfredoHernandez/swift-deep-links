//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import os

/// Remembers the nonces of signed links already opened, so each signed link
/// works once.
public protocol NonceStore: Sendable {
	/// Records `nonce` if it has not been seen.
	///
	/// Must check and record atomically: concurrent calls with the same
	/// nonce return `true` at most once.
	///
	/// - Parameters:
	///   - nonce: The link's nonce.
	///   - expiresAt: When the link expires; the nonce need not be kept after it.
	/// - Returns: `true` the first time `nonce` is consumed, `false` when it was
	///   already used or cannot be recorded.
	func consume(_ nonce: String, expiresAt: Date) async -> Bool
}

/// A bounded in-memory ``NonceStore``.
///
/// Nonces are kept until their link expires; expired entries are pruned only
/// when the store is full, so a consume is O(1) until then. When `maxEntries`
/// live nonces are stored, new nonces are **rejected** rather than evicting a
/// live one (which would let that link be replayed); size `maxEntries` above the
/// number of signed links you expect to be opened within one link lifetime.
/// Nonces are consumed only after a link's signature is verified, so an
/// attacker without the key cannot fill the store.
///
/// The record does not survive a relaunch; persist nonces in your own
/// ``NonceStore`` when links must stay single-use across launches.
public final class InMemoryNonceStore: NonceStore {
	private let maxEntries: Int
	private let dateProvider: @Sendable () -> Date
	private let expiries = OSAllocatedUnfairLock<[String: Date]>(initialState: [:])

	/// Creates a nonce store.
	///
	/// - Parameters:
	///   - maxEntries: Maximum number of live nonces; clamped to at least `1`.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(maxEntries: Int = 1000, dateProvider: @Sendable @escaping () -> Date = Date.init) {
		self.maxEntries = max(maxEntries, 1)
		self.dateProvider = dateProvider
	}

	public func consume(_ nonce: String, expiresAt: Date) async -> Bool {
		let now = dateProvider()
		return expiries.withLock { expiries in
			guard expiresAt > now else { return false }
			if let knownExpiry = expiries[nonce] {
				guard knownExpiry <= now else { return false }
			} else if expiries.count >= maxEntries {
				expiries = expiries.filter { $0.value > now }
				guard expiries.count < maxEntries else { return false }
			}
			expiries[nonce] = expiresAt
			return true
		}
	}
}
