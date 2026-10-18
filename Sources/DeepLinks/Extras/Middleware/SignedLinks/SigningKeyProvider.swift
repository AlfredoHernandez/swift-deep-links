//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation

/// Supplies the keys ``SignedLinkMiddleware`` verifies signatures with.
///
/// Keep several keys live while rotating: sign new links with the new key
/// (and its id in the link's `kid` parameter) and keep the old key until
/// every link signed with it has expired. Load keys from the Keychain or
/// your configuration; never ship them in the URL.
public protocol SigningKeyProvider: Sendable {
	/// The key for `keyID`, or `nil` when it is unknown or retired.
	///
	/// - Parameter keyID: The link's key id, or `nil` when the link carries none.
	/// - Returns: The verification key, or `nil` to reject the link.
	func verificationKey(forKeyID keyID: String?) async -> SymmetricKey?
}

/// A fixed set of signing keys, indexed by key id.
public struct SigningKeyring: SigningKeyProvider {
	/// The id ``init(key:)`` registers its key under.
	public static let defaultKeyID = "default"

	private let keys: [String: SymmetricKey]
	private let defaultKeyID: String?

	/// Creates a keyring.
	///
	/// - Parameters:
	///   - keys: The live keys, by key id.
	///   - defaultKeyID: The key used for links without a key id; `nil`
	///     (default) rejects such links.
	public init(keys: [String: SymmetricKey], defaultKeyID: String? = nil) {
		self.keys = keys
		self.defaultKeyID = defaultKeyID
	}

	/// Creates a keyring with a single key, used for links without a key id
	/// and for links whose key id is ``defaultKeyID``.
	///
	/// - Parameter key: The signing key.
	public init(key: SymmetricKey) {
		self.init(keys: [Self.defaultKeyID: key], defaultKeyID: Self.defaultKeyID)
	}

	/// The key for `keyID`, or for ``defaultKeyID`` when the link has no key id.
	///
	/// - Returns: `nil` for an unknown key id, or for a link without one when
	///   there is no default key; the link then fails as an invalid signature.
	public func verificationKey(forKeyID keyID: String?) async -> SymmetricKey? {
		(keyID ?? defaultKeyID).flatMap { keys[$0] }
	}
}

#endif
