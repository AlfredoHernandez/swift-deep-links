//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// The query parameter names a signed link uses.
///
/// ``SignedLinkBuilder`` and ``SignedLinkMiddleware`` must agree on them, and
/// so must any server that signs links.
public struct SignedLinkParameters: Sendable, Hashable {
	/// The default names: `sig`, `exp`, `nonce` and `kid`.
	public static let `default` = SignedLinkParameters()

	/// The parameter carrying the unpadded base64url HMAC-SHA256 signature.
	public var signature: String

	/// The parameter carrying the expiry, in whole seconds since 1970-01-01T00:00:00Z.
	public var expiry: String

	/// The parameter carrying a single-use nonce.
	public var nonce: String

	/// The parameter naming the signing key, for key rotation.
	public var keyID: String

	/// Creates a set of parameter names.
	public init(signature: String = "sig", expiry: String = "exp", nonce: String = "nonce", keyID: String = "kid") {
		self.signature = signature
		self.expiry = expiry
		self.nonce = nonce
		self.keyID = keyID
	}

	var all: Set<String> {
		[signature, expiry, nonce, keyID]
	}
}
