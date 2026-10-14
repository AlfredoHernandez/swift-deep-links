//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation

/// Signs deep links for ``SignedLinkMiddleware``.
///
/// Use it on a server written in Swift, in tests, or as the reference for a
/// server in another language: the signature is the unpadded base64url
/// HMAC-SHA256, with the shared key, of the canonical form documented on
/// ``SignedLinkMiddleware``.
///
/// ```swift
/// let builder = SignedLinkBuilder(key: key, keyID: "2026-10")
/// let link = try builder.sign(
///     URL(string: "https://example.com/reset?user=42")!,
///     expiresAt: .now.addingTimeInterval(900),
///     nonce: UUID().uuidString
/// )
/// // https://example.com/reset?user=42&kid=2026-10&exp=…&nonce=…&sig=…
/// ```
public struct SignedLinkBuilder: Sendable {
	private let key: SymmetricKey
	private let keyID: String?
	private let parameters: SignedLinkParameters

	/// Creates a builder.
	///
	/// - Parameters:
	///   - key: The signing key; use at least 256 random bits.
	///   - keyID: The key's id, added as the key-id parameter so the verifier
	///     can pick the key during rotation. `nil` (default) adds none.
	///   - parameters: The query parameter names. Defaults to ``SignedLinkParameters/default``.
	public init(key: SymmetricKey, keyID: String? = nil, parameters: SignedLinkParameters = .default) {
		self.key = key
		self.keyID = keyID
		self.parameters = parameters
	}

	/// Returns `url` with the key id, expiry, nonce and signature appended, in that order.
	///
	/// - Parameters:
	///   - url: The link to sign.
	///   - expiresAt: When the link stops working, rounded down to whole seconds.
	///   - nonce: A unique, unguessable value making the link single-use when
	///     the verifier has a ``NonceStore``.
	/// - Returns: The signed link.
	/// - Throws: ``DeepLinkError/invalidURL(_:)`` when `url` cannot be decomposed
	///   or already carries one of the signed-link parameters.
	public func sign(_ url: URL, expiresAt: Date? = nil, nonce: String? = nil) throws(DeepLinkError) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      !(components.percentEncodedQueryItems ?? []).contains(where: { parameters.all.contains(SignedLinkCanonicalForm.decodedName(of: $0)) })
		else { throw DeepLinkError.invalidURL(url) }

		let added = [
			keyID.map { (parameters.keyID, $0) },
			expiresAt.map { (parameters.expiry, String(Int64($0.timeIntervalSince1970.rounded(.down)))) },
			nonce.map { (parameters.nonce, $0) },
		].compactMap(\.self)
		components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? [])
			+ added.map { URLQueryItem(name: Self.encoded($0.0), value: Self.encoded($0.1)) }

		guard let unsigned = components.url else { throw DeepLinkError.invalidURL(url) }
		let signature = SignedLinkCanonicalForm.signature(of: unsigned, parameters: parameters, using: key)
		components.percentEncodedQueryItems?.append(URLQueryItem(name: Self.encoded(parameters.signature), value: signature))

		guard let signed = components.url else { throw DeepLinkError.invalidURL(url) }
		return signed
	}

	private static func encoded(_ text: String) -> String {
		text.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? text
	}

	private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
}

#endif
