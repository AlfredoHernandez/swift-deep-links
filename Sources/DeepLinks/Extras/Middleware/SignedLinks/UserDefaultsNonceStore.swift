//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A bounded ``NonceStore`` that keeps spent nonces in `UserDefaults`, so a
/// signed link stays single-use across relaunches.
///
/// Spent nonces are stored with their link's expiry and pruned once expired
/// (when the store loads and when it is full). Reservations live in memory
/// only and are **dropped on relaunch**: a link interrupted by termination
/// (including one waiting in a readiness queue, which does not survive
/// relaunch either) never completed, so it may be opened again. The one gap is a link whose
/// handler finished just before the app was killed and before the commit was
/// written; it could run once more after relaunch, within its expiry.
///
/// `UserDefaults` is readable and writable by anyone with access to the
/// device's app container, and unreadable data starts an empty store, so treat
/// this as protection against accidental and remote replays, not against a
/// user tampering with their own device. Checks are atomic within the process
/// (the store is an actor and never suspends mid-check); do not share one
/// `key` between several stores.
public actor UserDefaultsNonceStore: NonceStore {
	/// The default key holding the spent nonces.
	public static let defaultKey = "deeplink.signed-links.nonces"

	private struct Stored: Codable {
		var version = 1
		var spent: [String: Date]
	}

	private let userDefaults: UserDefaults
	private let key: String
	private let maxEntries: Int
	private let reservationTTL: TimeInterval
	private let dateProvider: @Sendable () -> Date
	private var loadedLedger: NonceLedger?

	/// Creates a store over `userDefaults`.
	///
	/// - Parameters:
	///   - userDefaults: The defaults database. Defaults to `.standard`.
	///   - key: The key holding the spent nonces. Defaults to ``defaultKey``.
	///   - maxEntries: Maximum number of live nonces, reservations included;
	///     clamped to at least `1`. New nonces are rejected when it is reached.
	///   - reservationTTL: How long an unsettled reservation holds a nonce.
	///     Defaults to ``InMemoryNonceStore/defaultReservationTTL``.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		userDefaults: UserDefaults = .standard,
		key: String = UserDefaultsNonceStore.defaultKey,
		maxEntries: Int = 1000,
		reservationTTL: TimeInterval = InMemoryNonceStore.defaultReservationTTL,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.userDefaults = userDefaults
		self.key = key
		self.maxEntries = max(maxEntries, 1)
		self.reservationTTL = reservationTTL > 0 ? reservationTTL : 0
		self.dateProvider = dateProvider
	}

	public func consume(_ nonce: String, expiresAt: Date) async -> Bool {
		let now = dateProvider()
		return updatingLedger { $0.admit(nonce, expiresAt: expiresAt, reservation: nil, now: now, maxEntries: maxEntries) }
	}

	public func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
		let now = dateProvider()
		let reservation = NonceReservation(nonce: nonce, expiresAt: expiresAt)
		let hold = NonceLedger.Hold(token: reservation.token, until: now.addingTimeInterval(reservationTTL))
		let admitted = updatingLedger { $0.admit(nonce, expiresAt: expiresAt, reservation: hold, now: now, maxEntries: maxEntries) }
		return admitted ? reservation : nil
	}

	public func commit(_ reservation: NonceReservation) async {
		let now = dateProvider()
		updatingLedger { $0.commit(reservation, now: now) }
	}

	public func release(_ reservation: NonceReservation) async {
		updatingLedger { $0.release(reservation) }
	}
}

// MARK: - Persistence

private extension UserDefaultsNonceStore {
	@discardableResult
	func updatingLedger<Output>(_ update: (inout NonceLedger) -> Output) -> Output {
		var ledger = loadedLedger ?? loadLedger()
		let output = update(&ledger)
		loadedLedger = ledger
		persist(ledger)
		return output
	}

	func loadLedger() -> NonceLedger {
		var ledger = NonceLedger()
		if let data = userDefaults.data(forKey: key),
		   let stored = try? JSONDecoder().decode(Stored.self, from: data),
		   stored.version == 1
		{
			ledger.entries = stored.spent.mapValues { NonceLedger.Entry(expiresAt: $0, hold: nil) }
		}
		ledger.prune(at: dateProvider())
		return ledger
	}

	func persist(_ ledger: NonceLedger) {
		let spent = ledger.entries.compactMapValues { $0.hold == nil ? $0.expiresAt : nil }
		guard let data = try? JSONEncoder().encode(Stored(spent: spent)) else { return }
		userDefaults.set(data, forKey: key)
	}
}
