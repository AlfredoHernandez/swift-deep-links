//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation

/// Checks the signature of a signed link's canonical form for ``SignedLinkMiddleware``.
///
/// Two verifiers are built in: HMAC-SHA256 with shared keys (pass a
/// ``SigningKeyProvider`` as `keys:`) and Ed25519 with public keys
/// (``Ed25519PublicKeyring``). Prefer Ed25519 when links are minted by a
/// server: the app then holds only public keys, so extracting them from a
/// device cannot forge links, whereas an HMAC key on the device can.
public protocol SignedLinkVerifier: Sendable {
	/// Whether `signature` is valid for `message` under the key `keyID` names.
	///
	/// - Parameters:
	///   - signature: The decoded signature parameter.
	///   - message: The UTF-8 canonical form documented on ``SignedLinkMiddleware``.
	///   - keyID: The link's key id, or `nil` when it carries none.
	/// - Returns: `false` for an unknown key id or a signature that does not match.
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` for an unusable key configuration.
	func isValidSignature(_ signature: Data, of message: Data, keyID: String?) async throws -> Bool
}

/// Signs a signed link's canonical form for ``SignedLinkBuilder``.
public protocol SignedLinkSigner: Sendable {
	/// The signature of `message`, the UTF-8 canonical form documented on ``SignedLinkMiddleware``.
	///
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` for an unusable key.
	func signature(of message: Data) throws -> Data
}

// MARK: - HMAC-SHA256

/// Verifies HMAC-SHA256 signatures with the keys a ``SigningKeyProvider`` returns.
struct HMACSignedLinkVerifier: SignedLinkVerifier {
	let keys: any SigningKeyProvider

	func isValidSignature(_ signature: Data, of message: Data, keyID: String?) async throws -> Bool {
		guard let key = await keys.verificationKey(forKeyID: keyID) else { return false }
		try HMACKeyStrength.require(key)
		return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: message, using: key)
	}
}

/// Signs with HMAC-SHA256 and a shared key.
struct HMACSignedLinkSigner: SignedLinkSigner {
	let key: SymmetricKey

	func signature(of message: Data) throws -> Data {
		try HMACKeyStrength.require(key)
		return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
	}
}

enum HMACKeyStrength {
	static func require(_ key: SymmetricKey) throws(DeepLinkError) {
		guard key.bitCount >= SignedLinkMiddleware.minimumKeyByteCount * 8 else {
			throw .securityViolation(SignedLinkMiddleware.weakKeyReason)
		}
	}
}

// MARK: - Ed25519

/// Ed25519 public keys, indexed by key id, verifying links signed with the
/// matching private keys (``Ed25519LinkSigner``, or any RFC 8032 implementation).
///
/// The app embeds only public keys, so a key extracted from a device cannot
/// mint links. Rotate like ``SigningKeyring``: add the new key id, sign new
/// links with it, and remove the old one once its links have expired.
public struct Ed25519PublicKeyring: SignedLinkVerifier {
	/// The id ``init(key:)`` registers its key under.
	public static let defaultKeyID = SigningKeyring.defaultKeyID

	private let keys: [String: Curve25519.Signing.PublicKey]
	private let defaultKeyID: String?

	/// Creates a keyring.
	///
	/// - Parameters:
	///   - keys: The live public keys, by key id.
	///   - defaultKeyID: The key used for links without a key id; `nil` (default) rejects such links.
	public init(keys: [String: Curve25519.Signing.PublicKey], defaultKeyID: String? = nil) {
		self.keys = keys
		self.defaultKeyID = defaultKeyID
	}

	/// Creates a keyring with a single key, used for links without a key id
	/// and for links whose key id is ``defaultKeyID``.
	public init(key: Curve25519.Signing.PublicKey) {
		self.init(keys: [Self.defaultKeyID: key], defaultKeyID: Self.defaultKeyID)
	}

	/// Checks `signature` with the public key for `keyID`, or for
	/// ``defaultKeyID`` when the link has no key id.
	///
	/// - Returns: `false` for an unknown key id or a signature that does not
	///   verify; it never throws.
	public func isValidSignature(_ signature: Data, of message: Data, keyID: String?) async throws -> Bool {
		guard let key = (keyID ?? defaultKeyID).flatMap({ keys[$0] }) else { return false }
		return key.isValidSignature(signature, for: message)
	}
}

/// Signs links with an Ed25519 private key. Keep the private key on your
/// server; ship only its public key in an ``Ed25519PublicKeyring``.
public struct Ed25519LinkSigner: SignedLinkSigner {
	private let privateKey: Curve25519.Signing.PrivateKey

	/// Creates a signer.
	///
	/// - Parameter privateKey: The signing key.
	public init(privateKey: Curve25519.Signing.PrivateKey) {
		self.privateKey = privateKey
	}

	/// Signs `message` with the private key; the result verifies with the
	/// matching public key in an ``Ed25519PublicKeyring``.
	///
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` with
	///   ``SignedLinkMiddleware/signingFailedReason`` when CryptoKit cannot sign.
	public func signature(of message: Data) throws -> Data {
		do {
			return try privateKey.signature(for: message)
		} catch {
			throw DeepLinkError.securityViolation(SignedLinkMiddleware.signingFailedReason)
		}
	}
}

#endif
