//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation
import os

/// Middleware that requires a signature (HMAC-SHA256 or Ed25519), and optionally an
/// expiry and a single-use nonce, on sensitive deep links such as password
/// resets, invitations and payment confirmations.
///
/// A link the ``DeepLinkMatcher`` selects must carry a signature made with a
/// key the ``SigningKeyProvider`` (HMAC) or ``SignedLinkVerifier`` (for example
/// ``Ed25519PublicKeyring``) knows. Any other link that carries the
/// signature parameter is verified too (and rejected if the signature is
/// invalid), so route-level rules (``SignedRouteGuard``) can rely on it; links
/// without one pass through. Every link leaves with
/// ``DeepLinkContext/isSignatureVerified`` set to whether its signature was
/// verified here.
/// Sign links with ``SignedLinkBuilder`` or an equivalent server
/// implementation.
///
/// ## Canonical Form
///
/// The signature covers seven lines joined by `\n`: `DLSIG1`; the lower-cased
/// scheme; the lower-cased percent-encoded host; the port (or empty); the
/// percent-encoded path; every query item except the signature, rendered
/// `name=value` (or `name`), sorted by UTF-8 bytes and joined by `&`; and the
/// fragment (or empty). Path, query and fragment have escapes of unreserved
/// characters decoded and other escapes upper-cased. Changing any of these
/// (including adding a parameter or a fragment) invalidates the signature;
/// reordering the query or changing scheme/host case does not. The key id,
/// expiry and nonce are ordinary query items, so they are signed too.
/// Userinfo (`user:pass@`) is **not** covered: place ``SecurityMiddleware``
/// with ``SecurityStrategy/hardened`` first, which rejects it.
///
/// Links from every entry point go through the same check: a notification,
/// Spotlight item or quick action whose URL matches the rule must carry a
/// signed URL in its payload, or it is rejected like any unsigned link.
///
/// ## Keys
///
/// An HMAC key verifies **and** mints links, and anything shipped in an app
/// can be extracted from a device, so a leaked HMAC key lets an attacker
/// forge links for every install. Prefer ``Ed25519PublicKeyring``: the app
/// holds only public keys and your server keeps the private ones
/// (``Ed25519LinkSigner``). HMAC keys must be at least
/// ``minimumKeyByteCount`` bytes; a shorter one throws ``weakKeyReason``.
/// Nonce stores are per install: a nonce spent on one device is unknown to
/// another, so a signed link stays usable once on **every** device until it
/// expires. Keep lifetimes short, and cap them with `maximumLifetime`.
///
/// ## Checks, in order
///
/// 1. Exactly one signature, and at most one key id, expiry and nonce.
/// 2. The signature verifies (compared in constant time) with the key the
///    provider returns for the link's key id.
/// 3. The expiry (whole seconds since 1970) has not passed, extended by
///    `leeway` seconds after it, and is at most `maximumLifetime` seconds
///    ahead; required when `requiresExpiry` is `true`, a nonce store or a maximum lifetime is set.
/// 4. With a ``NonceStore``, the nonce is present and consumed for the first time.
///
/// Every failure throws ``DeepLinkError/securityViolation(_:)`` with one of
/// the fixed reasons below, which never include the key, the signature or the
/// link. An unknown key id fails like a bad signature.
///
/// ## Nonces
///
/// Inside ``DeepLinkCoordinator`` nonces are two-phase: the nonce is
/// **reserved** when the signature verifies (a concurrent delivery of the same
/// link is rejected as reused), then settled in
/// ``didFinish(_:outcome:)``: **committed** once a handler ran (including
/// ``DeepLinkOutcome/handlerFailed(_:)``: a handler may have acted before it
/// threw, or another route succeeded); **released** when a later middleware
/// or the router stopped or failed it before any handler ran, or a
/// ``DeepLinkReadinessQueue`` evicted or reset it. A link queued by readiness
/// keeps its reservation until it drains and is settled with that pass's
/// outcome, so the user can retry and a link saved by
/// ``AuthenticationMiddleware`` resumes once after sign-in. Keep handlers
/// idempotent where a repeat could double a side effect. A
/// reservation never settled lapses after the store's time to live. Called
/// directly (outside a coordinator) the middleware consumes at once. Nonces
/// are global, not scoped to a key id, so use unguessable values.
///
/// ## Placement
///
/// After ``SecurityMiddleware``, the rate limiter (verification costs an
/// HMAC) and ``ReplayProtectionMiddleware`` (so the same link delivered twice,
/// through `onOpenURL` and `NSUserActivity`, is dropped quietly instead of
/// failing as a reused nonce; or pass `reusedNonce: .drop`), and before
/// authentication and anything that reads parameters. With `stripsSignatureParameters` (the default) the
/// signature, key id, expiry and nonce are removed before the link continues,
/// so parsers see the link as it was before signing.
///
/// ```swift
/// .middleware(
///     .security(allowedSchemes: ["https"], allowedHosts: ["example.com"]),
///     .rateLimit(maxRequests: 20, timeWindow: 60),
///     .replayProtection(window: 2),
///     .signedLinks(
///         keys: SigningKeyring(keys: ["2026-10": currentKey, "2026-04": previousKey]),
///         requiredFor: .paths(["/reset", "/invite"]),
///         nonceStore: InMemoryNonceStore()
///     )
/// )
/// ```
public final class SignedLinkMiddleware: DeepLinkMiddleware {
	/// What happens to a verified link whose nonce was already consumed.
	public enum ReusedNonceResponse: Sendable {
		/// Throw ``DeepLinkError/securityViolation(_:)`` with ``reusedNonceReason``.
		case reject

		/// Stop the chain without an error; the result reports
		/// ``DeepLinkResult/wasStoppedByMiddleware``. Suits links that can be
		/// delivered twice (`onOpenURL` and `NSUserActivity`).
		case drop
	}

	/// The link has no signature.
	public static let missingSignatureReason = "Missing link signature"
	/// The signature is malformed, repeated, made with another key or does not match the link.
	public static let invalidSignatureReason = "Invalid link signature"
	/// The link has no expiry but one is required.
	public static let missingExpiryReason = "Missing link expiry"
	/// The expiry is not a whole number of seconds.
	public static let invalidExpiryReason = "Invalid link expiry"
	/// The link has expired.
	public static let expiredReason = "Expired signed link"
	/// The link has no nonce but a nonce store is configured.
	public static let missingNonceReason = "Missing link nonce"
	/// The link's nonce was already consumed.
	public static let reusedNonceReason = "Signed link already used"
	/// The link expires further ahead than `maximumLifetime` allows.
	public static let lifetimeTooLongReason = "Signed link lifetime too long"
	/// An HMAC key is shorter than ``minimumKeyByteCount`` bytes.
	public static let weakKeyReason = "Signing key too short"
	/// The signer could not produce a signature.
	public static let signingFailedReason = "Could not sign link"
	/// The shortest HMAC-SHA256 key accepted, in bytes (256 bits).
	public static let minimumKeyByteCount = 32

	private let verifier: any SignedLinkVerifier
	private let matcher: DeepLinkMatcher
	private let parameters: SignedLinkParameters
	private let requiresExpiry: Bool
	private let leeway: TimeInterval
	private let maximumLifetime: TimeInterval?
	private let nonceStore: (any NonceStore)?
	private let reusedNonce: ReusedNonceResponse
	private let stripsSignatureParameters: Bool
	private let dateProvider: @Sendable () -> Date
	private let settlements = OSAllocatedUnfairLock(initialState: NonceSettlements())

	/// Creates a middleware verifying HMAC-SHA256 signatures.
	///
	/// - Parameters:
	///   - keys: The verification keys, each at least ``minimumKeyByteCount`` bytes.
	///   - matcher: The links that must be signed. Defaults to ``DeepLinkMatcher/all``.
	///   - parameters: The query parameter names. Defaults to ``SignedLinkParameters/default``.
	///   - requiresExpiry: Whether a signed link must carry an expiry. Defaults to `true`.
	///   - leeway: Extra seconds a link stays valid **after** its expiry, to absorb
	///     clock skew; it never makes a link valid earlier. Defaults to `0`;
	///     negative, infinite and NaN values count as `0`.
	///   - maximumLifetime: The furthest ahead, in seconds, a link's expiry may be;
	///     a later expiry is rejected with ``lifetimeTooLongReason``, so a leaked
	///     key or a long-lived link cannot be used indefinitely. Requires an expiry.
	///     Defaults to `nil` (no cap).
	///   - nonceStore: Makes each link single-use and requires a nonce and an expiry. Defaults to `nil`.
	///   - reusedNonce: Whether a reused nonce is rejected (default) or dropped quietly.
	///   - stripsSignatureParameters: Whether verified links continue without the
	///     signature, key id, expiry and nonce parameters. Defaults to `true`.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public convenience init(
		keys: any SigningKeyProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		parameters: SignedLinkParameters = .default,
		requiresExpiry: Bool = true,
		leeway: TimeInterval = 0,
		maximumLifetime: TimeInterval? = nil,
		nonceStore: (any NonceStore)? = nil,
		reusedNonce: ReusedNonceResponse = .reject,
		stripsSignatureParameters: Bool = true,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.init(
			verifier: HMACSignedLinkVerifier(keys: keys),
			requiredFor: matcher,
			parameters: parameters,
			requiresExpiry: requiresExpiry,
			leeway: leeway,
			maximumLifetime: maximumLifetime,
			nonceStore: nonceStore,
			reusedNonce: reusedNonce,
			stripsSignatureParameters: stripsSignatureParameters,
			dateProvider: dateProvider,
		)
	}

	/// Creates a middleware verifying signatures with any ``SignedLinkVerifier``,
	/// such as an ``Ed25519PublicKeyring``.
	///
	/// The other parameters are those of
	/// ``init(keys:requiredFor:parameters:requiresExpiry:leeway:maximumLifetime:nonceStore:reusedNonce:stripsSignatureParameters:dateProvider:)``.
	public init(
		verifier: any SignedLinkVerifier,
		requiredFor matcher: DeepLinkMatcher = .all,
		parameters: SignedLinkParameters = .default,
		requiresExpiry: Bool = true,
		leeway: TimeInterval = 0,
		maximumLifetime: TimeInterval? = nil,
		nonceStore: (any NonceStore)? = nil,
		reusedNonce: ReusedNonceResponse = .reject,
		stripsSignatureParameters: Bool = true,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.verifier = verifier
		self.matcher = matcher
		self.parameters = parameters
		self.requiresExpiry = requiresExpiry
		self.leeway = leeway.isFinite && leeway > 0 ? leeway : 0
		self.maximumLifetime = maximumLifetime.map { $0.isNaN ? 0 : max($0, 0) }
		self.nonceStore = nonceStore
		self.reusedNonce = reusedNonce
		self.stripsSignatureParameters = stripsSignatureParameters
		self.dateProvider = dateProvider
	}

	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard matcher.matches(request) || carriesSignature(request.url) else {
			return request.markingSignature(verified: false)
		}

		let fields = try SignedLinkFields(url: request.url, parameters: parameters)
		try await verifySignature(of: fields, in: request.url)
		let validUntil = try validatedExpiry(fields.expiry)
		guard try await consumeNonce(fields.nonce, validUntil: validUntil) else { return nil }

		let verified = stripsSignatureParameters ? request.replacingURL(strippingSignatureParameters(from: request.url)) : request
		return verified.markingSignature(verified: true)
	}

	/// Spends the nonce reserved for this link once a handler ran, frees it when
	/// the link stopped or failed before any handler ran, and keeps it while a
	/// readiness queue holds the link (``DeepLinkOutcome/deferred``).
	public func didFinish(_: DeepLinkRequest, outcome: DeepLinkOutcome) async {
		if case .deferred = outcome {
			return
		}
		guard let nonceStore, let runID = DeepLinkRun.id,
		      let reservation = settlements.withLock({ $0.settle(runID) })
		else { return }

		switch outcome {
		case .succeeded, .handlerFailed, .deferred:
			await nonceStore.commit(reservation)

		case .stopped, .failed:
			await nonceStore.release(reservation)
		}
	}
}

// MARK: - Verification

private extension SignedLinkMiddleware {
	func verifySignature(of fields: SignedLinkFields, in url: URL) async throws {
		let message = SignedLinkCanonicalForm.message(of: url, parameters: parameters)
		guard try await verifier.isValidSignature(fields.signature, of: message, keyID: fields.keyID) else {
			throw DeepLinkError.securityViolation(Self.invalidSignatureReason)
		}
	}

	func validatedExpiry(_ expiry: String?) throws -> Date? {
		guard let expiry else {
			if requiresExpiry || nonceStore != nil || maximumLifetime != nil {
				throw DeepLinkError.securityViolation(Self.missingExpiryReason)
			}
			return nil
		}
		guard expiry.allSatisfy(\.isASCII), expiry.allSatisfy(\.isNumber), let seconds = Int64(expiry) else {
			throw DeepLinkError.securityViolation(Self.invalidExpiryReason)
		}
		let now = dateProvider()
		let validUntil = Date(timeIntervalSince1970: TimeInterval(seconds) + leeway)
		guard now < validUntil else {
			throw DeepLinkError.securityViolation(Self.expiredReason)
		}
		if let maximumLifetime, TimeInterval(seconds) - now.timeIntervalSince1970 > maximumLifetime {
			throw DeepLinkError.securityViolation(Self.lifetimeTooLongReason)
		}
		return validUntil
	}

	/// Returns `false` when a reused nonce should drop the link quietly.
	func consumeNonce(_ nonce: String?, validUntil: Date?) async throws -> Bool {
		guard let nonceStore, let validUntil else { return true }
		guard let nonce, !nonce.isEmpty else {
			throw DeepLinkError.securityViolation(Self.missingNonceReason)
		}
		if await admit(nonce, until: validUntil, in: nonceStore) {
			return true
		}
		switch reusedNonce {
		case .reject:
			throw DeepLinkError.securityViolation(Self.reusedNonceReason)

		case .drop:
			return false
		}
	}

	/// Inside a ``DeepLinkCoordinator`` pass the nonce is only reserved and
	/// settled in ``didFinish(_:outcome:)``; called directly, it is consumed.
	///
	/// A nonce whose link is still being processed by this middleware is
	/// rejected whatever the store says, so a store reservation that lapses
	/// mid-link (a long confirmation prompt) never lets the link run twice.
	func admit(_ nonce: String, until validUntil: Date, in nonceStore: any NonceStore) async -> Bool {
		let now = dateProvider()
		guard let runID = DeepLinkRun.id else {
			guard !settlements.withLock({ $0.isInFlight(nonce, at: now) }) else { return false }
			return await nonceStore.consume(nonce, expiresAt: validUntil)
		}
		guard settlements.withLock({ $0.claim(nonce, until: validUntil, at: now) }) else { return false }
		guard let reservation = await nonceStore.reserve(nonce, expiresAt: validUntil) else {
			settlements.withLock { $0.unclaim(nonce) }
			return false
		}
		settlements.withLock { $0.hold(reservation, for: runID) }
		return true
	}

	func carriesSignature(_ url: URL) -> Bool {
		(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? [])
			.contains { SignedLinkCanonicalForm.decodedName(of: $0) == parameters.signature }
	}

	func strippingSignatureParameters(from url: URL) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
		let kept = (components.percentEncodedQueryItems ?? []).filter {
			!parameters.all.contains(SignedLinkCanonicalForm.decodedName(of: $0))
		}
		components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
		return components.url ?? url
	}
}

// MARK: - Signed Link Fields

private struct SignedLinkFields {
	let signature: Data
	let keyID: String?
	let expiry: String?
	let nonce: String?

	init(url: URL, parameters: SignedLinkParameters) throws {
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems ?? []
		func values(of name: String) throws -> [String] {
			let values = items
				.filter { SignedLinkCanonicalForm.decodedName(of: $0) == name }
				.map { $0.value.flatMap(\.removingPercentEncoding) ?? "" }
			guard values.count <= 1 else {
				throw DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)
			}
			return values
		}

		guard let encodedSignature = try values(of: parameters.signature).first else {
			throw DeepLinkError.securityViolation(SignedLinkMiddleware.missingSignatureReason)
		}
		guard let signature = Base64URL.decoded(encodedSignature) else {
			throw DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)
		}
		self.signature = signature
		keyID = try values(of: parameters.keyID).first
		expiry = try values(of: parameters.expiry).first
		nonce = try values(of: parameters.nonce).first
	}
}

private extension DeepLinkRequest {
	func markingSignature(verified: Bool) -> DeepLinkRequest {
		var request = self
		request.context.signatureVerifiedURL = verified ? url : nil
		return request
	}
}

/// The reservations this middleware holds, by coordinator pass, and the
/// nonces whose links are still in flight in this process.
private struct NonceSettlements {
	private var byRun: [UUID: [NonceReservation]] = [:]
	private var inFlight: [String: Date] = [:]

	func isInFlight(_ nonce: String, at now: Date) -> Bool {
		inFlight[nonce].map { now < $0 } ?? false
	}

	/// Marks `nonce` in flight until its link expires, unless it already is.
	mutating func claim(_ nonce: String, until expiry: Date, at now: Date) -> Bool {
		guard !isInFlight(nonce, at: now) else { return false }
		inFlight[nonce] = expiry
		return true
	}

	mutating func unclaim(_ nonce: String) {
		inFlight[nonce] = nil
	}

	mutating func hold(_ reservation: NonceReservation, for runID: UUID) {
		byRun[runID, default: []].append(reservation)
	}

	/// Removes and returns the newest reservation of `runID`, ending its flight.
	mutating func settle(_ runID: UUID) -> NonceReservation? {
		guard let reservation = byRun[runID]?.popLast() else { return nil }
		if byRun[runID]?.isEmpty == true {
			byRun[runID] = nil
		}
		inFlight[reservation.nonce] = nil
		return reservation
	}
}

#endif
