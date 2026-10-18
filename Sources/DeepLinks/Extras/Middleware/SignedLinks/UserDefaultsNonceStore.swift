//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import OSLog

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
/// user tampering with their own device. Unreadable (corrupt) data is logged
/// and starts an empty store; data written by a **newer** format version is
/// kept untouched and the store **fails closed** (every nonce is refused) until
/// that data is cleared, so a downgrade never forgets spent nonces. A nonce
/// whose spending cannot be written is refused as well.
///
/// The store writes only when the set of spent nonces changes. Checks are
/// atomic within one process (the store is an actor and never suspends
/// mid-check), but **not across processes**: an app extension sharing the
/// same suite (an app group) has its own copy in memory and can admit a nonce
/// the app already spent. Use one store per process with distinct keys, or a
/// server-side ``NonceStore``, when several processes open signed links.
public actor UserDefaultsNonceStore: NonceStore {
	/// The default key holding the spent nonces.
	public static let defaultKey = "deeplink.signed-links.nonces"

	static let formatVersion = 1

	struct Stored: Codable {
		var version = UserDefaultsNonceStore.formatVersion
		var spent: [String: Date]
	}

	private struct VersionProbe: Decodable {
		var version: Int
	}

	enum Loaded {
		case ready(NonceLedger)
		case unsupportedVersion
	}

	private let userDefaults: UserDefaults
	private let key: String
	private let maxEntries: Int
	private let reservationTTL: TimeInterval
	private let dateProvider: @Sendable () -> Date
	private let encode: @Sendable (Stored) throws -> Data
	private let log = Logger(subsystem: "swift-deep-links", category: "UserDefaultsNonceStore")
	private var loaded: Loaded?

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
		self.init(
			userDefaults: userDefaults,
			key: key,
			maxEntries: maxEntries,
			reservationTTL: reservationTTL,
			dateProvider: dateProvider,
			encode: { try JSONEncoder().encode($0) },
		)
	}

	init(
		userDefaults: UserDefaults,
		key: String,
		maxEntries: Int,
		reservationTTL: TimeInterval,
		dateProvider: @Sendable @escaping () -> Date,
		encode: @Sendable @escaping (Stored) throws -> Data,
	) {
		self.userDefaults = userDefaults
		self.key = key
		self.maxEntries = max(maxEntries, 1)
		self.reservationTTL = reservationTTL > 0 ? reservationTTL : 0
		self.dateProvider = dateProvider
		self.encode = encode
	}

	/// Spends `nonce` until `expiresAt` and writes the spent set.
	///
	/// Returns `false`, recording nothing, when the nonce is spent or reserved,
	/// `expiresAt` is not in the future, the store is full, the stored data has
	/// a newer format version, or the write fails.
	public func consume(_ nonce: String, expiresAt: Date) async -> Bool {
		let now = dateProvider()
		return updatingLedger(refusal: false) { $0.admit(nonce, expiresAt: expiresAt, reservation: nil, now: now, maxEntries: maxEntries) }
	}

	/// Holds `nonce` in memory for the reservation time to live; nothing is
	/// written, so the reservation does not survive a relaunch.
	///
	/// - Returns: The reservation, or `nil` for the same reasons ``consume(_:expiresAt:)`` returns `false`.
	public func reserve(_ nonce: String, expiresAt: Date) async -> NonceReservation? {
		let now = dateProvider()
		let reservation = NonceReservation(nonce: nonce, expiresAt: expiresAt)
		let hold = NonceLedger.Hold(token: reservation.token, until: now.addingTimeInterval(reservationTTL))
		let admitted = updatingLedger(refusal: false) {
			$0.admit(nonce, expiresAt: expiresAt, reservation: hold, now: now, maxEntries: maxEntries)
		}
		return admitted ? reservation : nil
	}

	/// Spends the reserved nonce until `reservation.expiresAt` and writes it.
	///
	/// If the write fails the nonce is still spent for this launch, so the link
	/// cannot run again before a relaunch. Like ``InMemoryNonceStore``, a
	/// lapsed or replaced reservation is spent anyway.
	public func commit(_ reservation: NonceReservation) async {
		let now = dateProvider()
		updatingLedger(refusal: (), keepingUnpersisted: true) { $0.commit(reservation, now: now) }
	}

	/// Frees the nonce while this reservation still holds it; a spent nonce or
	/// a newer reservation is left alone. Nothing is written for a reservation.
	public func release(_ reservation: NonceReservation) async {
		updatingLedger(refusal: ()) { $0.release(reservation) }
	}
}

// MARK: - Persistence

private extension UserDefaultsNonceStore {
	/// Applies `update` and writes the spent nonces when they changed.
	///
	/// Returns `refusal` without changing anything when stored data has an
	/// unsupported version, or when the write fails, unless
	/// `keepingUnpersisted` (a commit is kept in memory even if it cannot be
	/// written, which still protects this launch).
	func updatingLedger<Output>(
		refusal: Output,
		keepingUnpersisted: Bool = false,
		_ update: (inout NonceLedger) -> Output,
	) -> Output {
		guard case var .ready(ledger) = loaded ?? load() else { return refusal }
		let spentBefore = Self.spent(in: ledger)
		let output = update(&ledger)
		let spentAfter = Self.spent(in: ledger)
		if spentAfter != spentBefore, !persist(spentAfter), !keepingUnpersisted {
			return refusal
		}
		loaded = .ready(ledger)
		return output
	}

	func load() -> Loaded {
		var ledger = NonceLedger()
		if let data = userDefaults.data(forKey: key) {
			guard let version = try? JSONDecoder().decode(VersionProbe.self, from: data).version else {
				log.error("Unreadable spent nonces; starting empty")
				return remember(.ready(ledger))
			}
			guard version == Self.formatVersion, let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
				log.error("Spent nonces stored in unsupported format version \(version, privacy: .public); refusing every nonce")
				return remember(.unsupportedVersion)
			}
			ledger.entries = stored.spent.mapValues { NonceLedger.Entry(expiresAt: $0, hold: nil) }
		}
		ledger.prune(at: dateProvider())
		return remember(.ready(ledger))
	}

	func remember(_ state: Loaded) -> Loaded {
		loaded = state
		return state
	}

	func persist(_ spent: [String: Date]) -> Bool {
		do {
			try userDefaults.set(encode(Stored(spent: spent)), forKey: key)
			return true
		} catch {
			log.error("Could not write spent nonces: \(String(describing: type(of: error)), privacy: .public)")
			return false
		}
	}

	static func spent(in ledger: NonceLedger) -> [String: Date] {
		ledger.entries.compactMapValues { $0.hold == nil ? $0.expiresAt : nil }
	}
}
