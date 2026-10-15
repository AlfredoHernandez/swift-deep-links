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

	/// Holds `nonce` for a link that is still being processed.
	///
	/// While reserved, the nonce cannot be reserved or consumed again. The
	/// caller then commits the reservation (the link succeeded; the nonce is
	/// spent until `expiresAt`) or releases it (the link failed; it may be
	/// retried). A reservation that is neither committed nor released lapses
	/// after a store-defined time to live. Must be atomic like ``consume(_:expiresAt:)``.
	///
	/// The default consumes the nonce at once, so stores implementing only
	/// ``consume(_:expiresAt:)`` keep working but cannot release. Declare your
	/// implementations `async`: a synchronous actor method of the same name
	/// loses overload resolution to this default in async callers.
	///
	/// - Returns: The reservation, or `nil` when the nonce is in use, spent or cannot be recorded.
	func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation?

	/// Spends a reserved nonce until its link expires. The default does nothing.
	func commit(_ reservation: NonceReservation) async

	/// Frees a reserved nonce so the link can be retried; a reservation that
	/// already lapsed or was replaced is left alone. The default does nothing.
	func release(_ reservation: NonceReservation) async
}

public extension NonceStore {
	/// Consumes `nonce` at once and wraps the outcome in a reservation.
	///
	/// The nonce is already spent when this returns, so ``commit(_:)`` and
	/// ``release(_:)`` cannot undo it: with this default a link rejected after
	/// its signature verified (by authentication, a confirmation or a parser)
	/// cannot be retried or resumed after sign-in.
	///
	/// - Returns: A reservation when ``consume(_:expiresAt:)`` returned `true`, otherwise `nil`.
	func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
		await consume(nonce, expiresAt: expiresAt) ? NonceReservation(nonce: nonce, expiresAt: expiresAt) : nil
	}

	/// Does nothing: the default ``reserve(_:expiresAt:)`` already spent the nonce.
	func commit(_: NonceReservation) async {}

	/// Does nothing, so with the default ``reserve(_:expiresAt:)`` a released
	/// link stays spent.
	func release(_: NonceReservation) async {}
}

/// A nonce held by ``NonceStore/reserve(_:expiresAt:)`` until it is committed or released.
public struct NonceReservation: Sendable, Hashable, Codable {
	/// The reserved nonce.
	public let nonce: String

	/// When the signed link expires.
	public let expiresAt: Date

	/// Distinguishes this reservation from a later one for the same nonce.
	public let token: UUID

	/// Creates a reservation.
	public init(nonce: String, expiresAt: Date, token: UUID = UUID()) {
		self.nonce = nonce
		self.expiresAt = expiresAt
		self.token = token
	}
}

/// A bounded in-memory ``NonceStore``.
///
/// Nonces are kept until their link expires; expired entries are pruned only
/// when the store is full, so a consume is O(1) until then. When `maxEntries`
/// live nonces are stored, new nonces are **rejected** rather than evicting a
/// live one (which would let that link be replayed); size `maxEntries` above the
/// number of signed links you expect to be opened within one link lifetime.
/// Nonces are consumed only after a link's signature is verified, so an
/// attacker without the key cannot fill the store. Reservations count towards
/// `maxEntries` and lapse after `reservationTTL` if never committed or released.
///
/// The record does not survive a relaunch; use ``UserDefaultsNonceStore``
/// when links must stay single-use across launches.
public final class InMemoryNonceStore: NonceStore {
	/// The default time a reservation holds a nonce without being committed or released.
	public static let defaultReservationTTL: TimeInterval = 300

	private let maxEntries: Int
	private let reservationTTL: TimeInterval
	private let dateProvider: @Sendable () -> Date
	private let ledger = OSAllocatedUnfairLock(initialState: NonceLedger())

	/// Creates a nonce store.
	///
	/// - Parameters:
	///   - maxEntries: Maximum number of live nonces, reservations included; clamped to at least `1`.
	///   - reservationTTL: How long a reservation holds a nonce if it is never
	///     committed or released (for example the app was suspended mid-link).
	///     ``SignedLinkMiddleware`` also refuses a nonce whose link it is still
	///     processing, so a lapse never lets a link run twice in this process;
	///     the time to live matters across processes and middleware instances
	///     sharing the store, so keep it longer than your slowest confirmation
	///     prompt (give prompts a `timeout`). Defaults to
	///     ``defaultReservationTTL``; negative and NaN values count as `0`.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		maxEntries: Int = 1000,
		reservationTTL: TimeInterval = InMemoryNonceStore.defaultReservationTTL,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.maxEntries = max(maxEntries, 1)
		self.reservationTTL = reservationTTL > 0 ? reservationTTL : 0
		self.dateProvider = dateProvider
	}

	/// Spends `nonce` until `expiresAt`, atomically.
	///
	/// Returns `false`, recording nothing, when `nonce` is already spent or
	/// reserved, when `expiresAt` is not in the future, or when `maxEntries`
	/// live nonces remain after expired ones are pruned (a full store refuses
	/// rather than forgets).
	public func consume(_ nonce: String, expiresAt: Date) async -> Bool {
		let now = dateProvider()
		return ledger.withLock { $0.admit(nonce, expiresAt: expiresAt, reservation: nil, now: now, maxEntries: maxEntries) }
	}

	/// Holds `nonce` for `reservationTTL` seconds, atomically, counting it
	/// towards `maxEntries`.
	///
	/// Refused for the same reasons as ``consume(_:expiresAt:)``. A lapsed
	/// reservation frees the nonce for a new one; committing the lapsed
	/// reservation afterwards still spends it.
	///
	/// - Returns: The reservation, or `nil` when refused.
	public func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
		let now = dateProvider()
		let reservation = NonceReservation(nonce: nonce, expiresAt: expiresAt)
		let hold = NonceLedger.Hold(token: reservation.token, until: now.addingTimeInterval(reservationTTL))
		let admitted = ledger.withLock { $0.admit(nonce, expiresAt: expiresAt, reservation: hold, now: now, maxEntries: maxEntries) }
		return admitted ? reservation : nil
	}

	/// Spends the reserved nonce until `reservation.expiresAt`.
	///
	/// The nonce ends up spent even if the reservation lapsed or another
	/// reservation now holds it: a link whose handler ran must never run again.
	public func commit(_ reservation: NonceReservation) async {
		let now = dateProvider()
		ledger.withLock { $0.commit(reservation, now: now) }
	}

	/// Frees the nonce so its link can be retried, but only while this
	/// reservation (matched by ``NonceReservation/token``) still holds it; a
	/// spent nonce or a newer reservation is left alone.
	public func release(_ reservation: NonceReservation) async {
		ledger.withLock { $0.release(reservation) }
	}
}

/// The nonce bookkeeping shared by the built-in stores: spent nonces until
/// their link expires, reserved ones until committed, released or lapsed.
struct NonceLedger: Codable, Sendable {
	struct Hold: Codable, Sendable {
		var token: UUID
		var until: Date
	}

	struct Entry: Codable, Sendable {
		var expiresAt: Date
		var hold: Hold?

		func isLive(at now: Date) -> Bool {
			now < expiresAt && hold.map { now < $0.until } ?? true
		}
	}

	var entries: [String: Entry] = [:]

	/// Records `nonce` as spent (`reservation == nil`) or reserved. Expired
	/// entries are pruned only when the ledger is full.
	mutating func admit(_ nonce: String, expiresAt: Date, reservation: Hold?, now: Date, maxEntries: Int) -> Bool {
		guard expiresAt > now else { return false }
		if let entry = entries[nonce] {
			guard !entry.isLive(at: now) else { return false }
		} else if entries.count >= maxEntries {
			prune(at: now)
			guard entries.count < maxEntries else { return false }
		}
		entries[nonce] = Entry(expiresAt: expiresAt, hold: reservation)
		return true
	}

	mutating func commit(_ reservation: NonceReservation, now: Date) {
		if let entry = entries[reservation.nonce], entry.hold == nil, entry.isLive(at: now) {
			return
		}
		entries[reservation.nonce] = Entry(expiresAt: reservation.expiresAt, hold: nil)
	}

	mutating func release(_ reservation: NonceReservation) {
		guard entries[reservation.nonce]?.hold?.token == reservation.token else { return }
		entries[reservation.nonce] = nil
	}

	mutating func prune(at now: Date) {
		entries = entries.filter { $0.value.isLive(at: now) }
	}
}
