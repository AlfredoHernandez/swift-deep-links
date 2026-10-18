//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

/// The query parameter names a signed link uses.
///
/// ``SignedLinkBuilder`` and ``SignedLinkMiddleware`` must agree on them, and
/// so must any server that signs links. The defaults (`dlsig`, `dlexp`,
/// `dlnonce`, `dlkid`) are unlikely to clash with an app's own parameters:
/// any link carrying the signature parameter is verified, so a generic name
/// such as `sig` would make unrelated links fail as badly signed.
///
/// Since 2.0.1. Links minted by 2.0.0 use ``legacy``: pass `.legacy` to the
/// middleware until every such link has expired (and to the builder if your
/// server keeps minting them), then switch both to ``default``.
public struct SignedLinkParameters: Sendable, Hashable {
	/// The default names: `dlsig`, `dlexp`, `dlnonce` and `dlkid`.
	public static let `default` = SignedLinkParameters()

	/// The 2.0.0 default names: `sig`, `exp`, `nonce` and `kid`.
	public static let legacy = SignedLinkParameters(signature: "sig", expiry: "exp", nonce: "nonce", keyID: "kid")

	/// The parameter carrying the unpadded base64url HMAC-SHA256 signature.
	public var signature: String

	/// The parameter carrying the expiry, in whole seconds since 1970-01-01T00:00:00Z.
	public var expiry: String

	/// The parameter carrying a single-use nonce.
	public var nonce: String

	/// The parameter naming the signing key, for key rotation.
	public var keyID: String

	/// Creates a set of parameter names.
	public init(signature: String = "dlsig", expiry: String = "dlexp", nonce: String = "dlnonce", keyID: String = "dlkid") {
		self.signature = signature
		self.expiry = expiry
		self.nonce = nonce
		self.keyID = keyID
	}

	var all: Set<String> {
		[signature, expiry, nonce, keyID]
	}
}
