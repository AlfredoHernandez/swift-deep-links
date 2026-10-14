//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation
import os

/// Middleware that requires an HMAC-SHA256 signature, and optionally an
/// expiry and a single-use nonce, on sensitive deep links such as password
/// resets, invitations and payment confirmations.
///
/// A link the ``DeepLinkMatcher`` selects must carry a signature made with a
/// key the ``SigningKeyProvider`` knows; other links pass through untouched.
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
/// ## Checks, in order
///
/// 1. Exactly one signature, and at most one key id, expiry and nonce.
/// 2. The signature verifies (compared in constant time) with the key the
///    provider returns for the link's key id.
/// 3. The expiry (whole seconds since 1970) has not passed, extended by
///    `leeway` seconds after it; required when `requiresExpiry` is `true` or a nonce store is set.
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
/// ``didFinish(_:outcome:)``: **committed** when the link succeeded or a
/// ``ReadinessMiddleware`` queued it, **released** when a later middleware,
/// the router or a handler stopped or failed it, so the user can retry and a
/// link saved by ``AuthenticationMiddleware`` resumes once after sign-in. A
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

	private let keys: any SigningKeyProvider
	private let matcher: DeepLinkMatcher
	private let parameters: SignedLinkParameters
	private let requiresExpiry: Bool
	private let leeway: TimeInterval
	private let nonceStore: (any NonceStore)?
	private let reusedNonce: ReusedNonceResponse
	private let stripsSignatureParameters: Bool
	private let dateProvider: @Sendable () -> Date
	private let reservations = OSAllocatedUnfairLock<[UUID: NonceReservation]>(initialState: [:])

	/// Creates a signed-link middleware.
	///
	/// - Parameters:
	///   - keys: The verification keys.
	///   - matcher: The links that must be signed. Defaults to ``DeepLinkMatcher/all``.
	///   - parameters: The query parameter names. Defaults to ``SignedLinkParameters/default``.
	///   - requiresExpiry: Whether a signed link must carry an expiry. Defaults to `true`.
	///   - leeway: Extra seconds a link stays valid **after** its expiry, to absorb
	///     clock skew; it never makes a link valid earlier. Defaults to `0`;
	///     negative, infinite and NaN values count as `0`.
	///   - nonceStore: Makes each link single-use and requires a nonce and an expiry. Defaults to `nil`.
	///   - reusedNonce: Whether a reused nonce is rejected (default) or dropped quietly.
	///   - stripsSignatureParameters: Whether verified links continue without the
	///     signature, key id, expiry and nonce parameters. Defaults to `true`.
	///   - dateProvider: Supplies the current time; inject a manual clock in tests.
	public init(
		keys: any SigningKeyProvider,
		requiredFor matcher: DeepLinkMatcher = .all,
		parameters: SignedLinkParameters = .default,
		requiresExpiry: Bool = true,
		leeway: TimeInterval = 0,
		nonceStore: (any NonceStore)? = nil,
		reusedNonce: ReusedNonceResponse = .reject,
		stripsSignatureParameters: Bool = true,
		dateProvider: @Sendable @escaping () -> Date = Date.init,
	) {
		self.keys = keys
		self.matcher = matcher
		self.parameters = parameters
		self.requiresExpiry = requiresExpiry
		self.leeway = leeway.isFinite && leeway > 0 ? leeway : 0
		self.nonceStore = nonceStore
		self.reusedNonce = reusedNonce
		self.stripsSignatureParameters = stripsSignatureParameters
		self.dateProvider = dateProvider
	}

	public func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		guard matcher.matches(request) else { return request }

		let fields = try SignedLinkFields(url: request.url, parameters: parameters)
		try await verifySignature(of: fields, in: request.url)
		let validUntil = try validatedExpiry(fields.expiry)
		guard try await consumeNonce(fields.nonce, validUntil: validUntil) else { return nil }

		return stripsSignatureParameters ? request.replacingURL(strippingSignatureParameters(from: request.url)) : request
	}

	/// Spends the nonce reserved for this link when it succeeded or was queued
	/// for readiness, and frees it when a later stage stopped or failed it.
	public func didFinish(_: DeepLinkRequest, outcome: DeepLinkOutcome) async {
		guard let nonceStore, let runID = DeepLinkRun.id,
		      let reservation = reservations.withLock({ $0.removeValue(forKey: runID) })
		else { return }

		switch outcome {
		case .succeeded, .deferred:
			await nonceStore.commit(reservation)

		case .stopped, .failed:
			await nonceStore.release(reservation)
		}
	}
}

// MARK: - Verification

private extension SignedLinkMiddleware {
	func verifySignature(of fields: SignedLinkFields, in url: URL) async throws {
		guard let key = await keys.verificationKey(forKeyID: fields.keyID),
		      SignedLinkCanonicalForm.isValidSignature(fields.signature, of: url, parameters: parameters, using: key)
		else { throw DeepLinkError.securityViolation(Self.invalidSignatureReason) }
	}

	func validatedExpiry(_ expiry: String?) throws -> Date? {
		guard let expiry else {
			if requiresExpiry || nonceStore != nil {
				throw DeepLinkError.securityViolation(Self.missingExpiryReason)
			}
			return nil
		}
		guard expiry.allSatisfy(\.isASCII), expiry.allSatisfy(\.isNumber), let seconds = Int64(expiry) else {
			throw DeepLinkError.securityViolation(Self.invalidExpiryReason)
		}
		let validUntil = Date(timeIntervalSince1970: TimeInterval(seconds) + leeway)
		guard dateProvider() < validUntil else {
			throw DeepLinkError.securityViolation(Self.expiredReason)
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
	func admit(_ nonce: String, until validUntil: Date, in nonceStore: any NonceStore) async -> Bool {
		guard let runID = DeepLinkRun.id else {
			return await nonceStore.consume(nonce, expiresAt: validUntil)
		}
		guard let reservation = await nonceStore.reserve(nonce, expiresAt: validUntil) else { return false }
		reservations.withLock { $0[runID] = reservation }
		return true
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

#endif
