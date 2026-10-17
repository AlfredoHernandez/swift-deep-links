//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import Testing

struct SignedLinkKeysTests {
	// MARK: - Ed25519

	@Test
	func `Ed25519 verification matches the RFC 8032 test vector`() async throws {
		let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: hex(Self.rfcPublicKey))
		let signature = hex(Self.rfcSignature)
		var tampered = signature
		tampered[0] ^= 1
		let sut = Ed25519PublicKeyring(key: publicKey)

		#expect(try await sut.isValidSignature(signature, of: Data(), keyID: nil))
		#expect(try await !sut.isValidSignature(tampered, of: Data(), keyID: nil))
	}

	@Test
	func `Ed25519 middleware verifies the pinned reference link and strips its parameters`() async throws {
		let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_700_000_000))
		let sut = SignedLinkMiddleware(verifier: Ed25519PublicKeyring(keys: ["2026": Self.publicKey]), parameters: .legacy, dateProvider: clock.dateProvider)
		let link = try #require(URL(string: "https://example.com/reset?user=42&kid=2026&exp=1700000060&nonce=n-1&sig=\(Self.pinnedSignature)"))

		let verified = try await sut.intercept(DeepLinkRequest(url: link))

		#expect(verified?.url.absoluteString == "https://example.com/reset?user=42")
		#expect(verified?.context.isSignatureVerified == true)
	}

	@Test
	func `Ed25519 signer and public keyring round-trip and reject tampering`() async throws {
		let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_700_000_000))
		let builder = SignedLinkBuilder(signer: Ed25519LinkSigner(privateKey: Self.privateKey), keyID: "2026")
		let sut: SignedLinkMiddleware = .signedLinks(verifier: Ed25519PublicKeyring(keys: ["2026": Self.publicKey]), dateProvider: clock.dateProvider)
		let signed = try builder.sign(#require(URL(string: "myapp://invite?team=7")), expiresAt: Date(timeIntervalSince1970: 1_700_000_600))
		let tampered = try #require(URL(string: signed.absoluteString.replacingOccurrences(of: "team=7", with: "team=8")))

		#expect(try await sut.intercept(DeepLinkRequest(url: signed))?.url.absoluteString == "myapp://invite?team=7")
		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: tampered))
		}
	}

	@Test
	func `Ed25519 keyring rejects HMAC links and unknown key ids`() async throws {
		let sut = SignedLinkMiddleware(verifier: Ed25519PublicKeyring(keys: ["2026": Self.publicKey]), requiresExpiry: false, maximumLifetime: nil)
		let hmacSigned = try SignedLinkBuilder(key: SymmetricKey(size: .bits256), keyID: "2026").sign(#require(URL(string: "myapp://reset")))
		let otherKeyID = try SignedLinkBuilder(signer: Ed25519LinkSigner(privateKey: Self.privateKey), keyID: "old").sign(#require(URL(string: "myapp://reset")))

		for link in [hmacSigned, otherKeyID] {
			await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
				try await sut.intercept(DeepLinkRequest(url: link))
			}
		}
	}

	// MARK: - Key Size

	@Test
	func `builder refuses HMAC keys shorter than 256 bits`() throws {
		let builder = SignedLinkBuilder(key: SymmetricKey(data: Data(repeating: 1, count: 16)))

		#expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.weakKeyReason)) {
			try builder.sign(#require(URL(string: "myapp://reset")))
		}
	}

	@Test
	func `middleware refuses to verify with HMAC keys shorter than 256 bits`() async throws {
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: SymmetricKey(data: Data(repeating: 1, count: 31))), requiresExpiry: false, maximumLifetime: nil)
		let link = try #require(URL(string: "myapp://reset?dlsig=AAAA"))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.weakKeyReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	// MARK: - Maximum Lifetime

	@Test
	func `links expiring further ahead than the maximum lifetime are rejected`() async throws {
		let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_700_000_000))
		let builder = SignedLinkBuilder(key: Self.hmacKey)
		let sut: SignedLinkMiddleware = .signedLinks(keys: SigningKeyring(key: Self.hmacKey), maximumLifetime: 3600, dateProvider: clock.dateProvider)
		let tooLong = try builder.sign(#require(URL(string: "myapp://reset")), expiresAt: clock.now.addingTimeInterval(3601))
		let withinLimit = try builder.sign(#require(URL(string: "myapp://reset")), expiresAt: clock.now.addingTimeInterval(3600))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.lifetimeTooLongReason)) {
			try await sut.intercept(DeepLinkRequest(url: tooLong))
		}
		#expect(try await sut.intercept(DeepLinkRequest(url: withinLimit)) != nil)
	}

	@Test
	func `a maximum lifetime requires an expiry`() async throws {
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: Self.hmacKey), requiresExpiry: false, maximumLifetime: 3600)
		let link = try SignedLinkBuilder(key: Self.hmacKey).sign(#require(URL(string: "myapp://reset")))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingExpiryReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	// MARK: - Fixtures

	private static let rfcPublicKey = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
	private static let rfcSignature = "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
	private static let pinnedSignature = "nhHgdtVA3XMUhPclaiZmvNxPlKy1xMeeaJ3rIAc3U48mOjhDihiLzkwzu60-5Fm6zn3QC_lGgF1AnsLtQwxqBw"
	private static let privateKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(repeating: 1, count: 32))
	private static let publicKey = privateKey.publicKey
	private static let hmacKey = SymmetricKey(data: Data(repeating: 5, count: 32))
}

private func hex(_ text: String) -> Data {
	Data(stride(from: 0, to: text.count, by: 2).map { offset in
		let start = text.index(text.startIndex, offsetBy: offset)
		return UInt8(text[start ..< text.index(start, offsetBy: 2)], radix: 16) ?? 0
	})
}

#endif
