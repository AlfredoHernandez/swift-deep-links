//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

import CryptoKit
import Foundation

/// Signs deep links for ``SignedLinkMiddleware``.
///
/// Use it on a server written in Swift, in tests, or as the reference for a
/// server in another language: the signature is the unpadded base64url
/// HMAC-SHA256 (with the shared key) or Ed25519 signature (with an
/// ``Ed25519LinkSigner``) of the canonical form documented on
/// ``SignedLinkMiddleware``.
///
/// ```swift
/// let builder = SignedLinkBuilder(key: key, keyID: "2026-10")
/// let link = try builder.sign(
///     URL(string: "https://example.com/reset?user=42")!,
///     expiresAt: .now.addingTimeInterval(900),
///     nonce: UUID().uuidString
/// )
/// // https://example.com/reset?user=42&dlkid=2026-10&dlexp=…&dlnonce=…&dlsig=…
/// ```
public struct SignedLinkBuilder: Sendable {
	private let signer: any SignedLinkSigner
	private let keyID: String?
	private let parameters: SignedLinkParameters
	private let rejectDuplicateParameters: Bool

	/// Creates a builder.
	///
	/// - Parameters:
	///   - key: The HMAC-SHA256 signing key, at least
	///     ``SignedLinkMiddleware/minimumKeyByteCount`` random bytes; ``sign(_:expiresAt:nonce:)``
	///     throws for a shorter key.
	///   - keyID: The key's id, added as the key-id parameter so the verifier
	///     can pick the key during rotation. `nil` (default) adds none.
	///   - parameters: The query parameter names. Defaults to ``SignedLinkParameters/default``.
	///   - rejectDuplicateParameters: Whether ``sign(_:expiresAt:nonce:)`` refuses
	///     a link repeating a query parameter name. Defaults to `true`, matching
	///     ``SignedLinkMiddleware``, which rejects such links.
	public init(
		key: SymmetricKey,
		keyID: String? = nil,
		parameters: SignedLinkParameters = .default,
		rejectDuplicateParameters: Bool = true,
	) {
		self.init(
			signer: HMACSignedLinkSigner(key: key),
			keyID: keyID,
			parameters: parameters,
			rejectDuplicateParameters: rejectDuplicateParameters,
		)
	}

	/// Creates a builder signing with any ``SignedLinkSigner``, such as an ``Ed25519LinkSigner``.
	///
	/// - Parameters:
	///   - signer: Produces the signature of the canonical form.
	///   - keyID: The key's id, added as the key-id parameter. `nil` (default) adds none.
	///   - parameters: The query parameter names. Defaults to ``SignedLinkParameters/default``.
	///   - rejectDuplicateParameters: Whether ``sign(_:expiresAt:nonce:)`` refuses
	///     a link repeating a query parameter name. Defaults to `true`.
	public init(
		signer: any SignedLinkSigner,
		keyID: String? = nil,
		parameters: SignedLinkParameters = .default,
		rejectDuplicateParameters: Bool = true,
	) {
		self.signer = signer
		self.keyID = keyID
		self.parameters = parameters
		self.rejectDuplicateParameters = rejectDuplicateParameters
	}

	/// Returns `url` with the key id, expiry, nonce and signature appended, in that order.
	///
	/// - Parameters:
	///   - url: The link to sign.
	///   - expiresAt: When the link stops working, rounded down to whole seconds.
	///   - nonce: A unique, unguessable value making the link single-use when
	///     the verifier has a ``NonceStore``.
	/// - Returns: The signed link.
	/// - Throws: ``DeepLinkError/invalidURL(_:)`` when `url` cannot be decomposed,
	///   already carries one of the signed-link parameters, or repeats a query
	///   parameter name (decoded) while `rejectDuplicateParameters` is `true`;
	///   ``DeepLinkError/securityViolation(_:)`` when the signer cannot sign (an HMAC key that is too short).
	public func sign(_ url: URL, expiresAt: Date? = nil, nonce: String? = nil) throws(DeepLinkError) -> URL {
		guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
		      !(components.percentEncodedQueryItems ?? []).contains(where: { parameters.all.contains(SignedLinkCanonicalForm.decodedName(of: $0)) })
		else { throw DeepLinkError.invalidURL(url) }
		if rejectDuplicateParameters, SignedLinkCanonicalForm.repeatsParameterName(in: url) {
			throw DeepLinkError.invalidURL(url)
		}

		let added = [
			keyID.map { (parameters.keyID, $0) },
			expiresAt.map { (parameters.expiry, String(Int64($0.timeIntervalSince1970.rounded(.down)))) },
			nonce.map { (parameters.nonce, $0) },
		].compactMap(\.self)
		components.percentEncodedQueryItems = (components.percentEncodedQueryItems ?? [])
			+ added.map { URLQueryItem(name: Self.encoded($0.0), value: Self.encoded($0.1)) }

		guard let unsigned = components.url else { throw DeepLinkError.invalidURL(url) }
		let signature = try signature(of: unsigned)
		components.percentEncodedQueryItems?.append(URLQueryItem(name: Self.encoded(parameters.signature), value: signature))

		guard let signed = components.url else { throw DeepLinkError.invalidURL(url) }
		return signed
	}

	private func signature(of url: URL) throws(DeepLinkError) -> String {
		do {
			return try Base64URL.encoded(signer.signature(of: SignedLinkCanonicalForm.message(of: url, parameters: parameters)))
		} catch let error as DeepLinkError {
			throw error
		} catch {
			throw .securityViolation(SignedLinkMiddleware.signingFailedReason)
		}
	}

	private static func encoded(_ text: String) -> String {
		text.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? text
	}

	private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))
}

#endif
