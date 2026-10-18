//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import Testing

struct SignedLinkSaferDefaultsTests {
	private let clock = ManualDateProvider()
	private let privateKey = Curve25519.Signing.PrivateKey()

	// MARK: - Maximum Lifetime

	@Test
	func `the default maximum lifetime is seven days`() {
		#expect(SignedLinkMiddleware.defaultMaximumLifetime == 7 * 24 * 60 * 60)
	}

	@Test
	func `a link expiring further ahead than seven days is rejected by default`() async throws {
		let link = try sign(expiresAt: clock.now + SignedLinkMiddleware.defaultMaximumLifetime + 1)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.lifetimeTooLongReason)) {
			try await makeSUT().intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `a link expiring within seven days verifies by default`() async throws {
		let link = try sign(expiresAt: clock.now + SignedLinkMiddleware.defaultMaximumLifetime)

		#expect(try await makeSUT().intercept(DeepLinkRequest(url: link)) != nil)
	}

	@Test
	func `an explicit nil maximum lifetime accepts any future expiry`() async throws {
		let link = try sign(expiresAt: clock.now + 365 * 24 * 60 * 60)

		#expect(try await makeSUT(maximumLifetime: nil).intercept(DeepLinkRequest(url: link)) != nil)
	}

	@Test
	func `the factory applies the default maximum lifetime`() async throws {
		let link = try sign(expiresAt: clock.now + SignedLinkMiddleware.defaultMaximumLifetime + 1)
		let sut: SignedLinkMiddleware = .signedLinks(
			verifier: Ed25519PublicKeyring(key: privateKey.publicKey),
			nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider),
			dateProvider: clock.dateProvider,
		)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.lifetimeTooLongReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	// MARK: - Diagnostics

	@Test
	func `diagnostics warn about HMAC keys shipped in the app`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		let warnings = sut.checkMiddleware([
			.signedLinks(keys: SigningKeyring(key: SymmetricKey(size: .bits256)), nonceStore: InMemoryNonceStore()),
		])

		#expect(warnings == [.signedLinksWithSymmetricKey])
		#expect(DeepLinkDiagnosticWarning.signedLinksWithSymmetricKey.description.contains("Ed25519PublicKeyring"))
	}

	@Test
	func `diagnostics warn about signed links without a maximum lifetime`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		let warnings = sut.checkMiddleware([
			.signedLinks(verifier: Ed25519PublicKeyring(key: privateKey.publicKey), maximumLifetime: nil, nonceStore: InMemoryNonceStore()),
		])

		#expect(warnings == [.signedLinksWithoutMaximumLifetime])
		#expect(DeepLinkDiagnosticWarning.signedLinksWithoutMaximumLifetime.description.contains("maximumLifetime"))
	}

	@Test
	func `diagnostics report every weakness of one middleware`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		let warnings = sut.checkMiddleware([
			.signedLinks(keys: SigningKeyring(key: SymmetricKey(size: .bits256)), maximumLifetime: nil),
		])

		#expect(warnings == [.signedLinksWithSymmetricKey, .signedLinksWithoutMaximumLifetime, .signedLinksWithoutNonceStore])
	}

	@Test
	func `diagnostics accept Ed25519 keys with a nonce store and the default lifetime`() {
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		let warnings = sut.checkMiddleware([
			.signedLinks(verifier: Ed25519PublicKeyring(key: privateKey.publicKey), nonceStore: InMemoryNonceStore()),
		])

		#expect(warnings.isEmpty)
	}

	// MARK: - Helpers

	private func makeSUT() -> SignedLinkMiddleware {
		SignedLinkMiddleware(verifier: Ed25519PublicKeyring(key: privateKey.publicKey), dateProvider: clock.dateProvider)
	}

	private func makeSUT(maximumLifetime: TimeInterval?) -> SignedLinkMiddleware {
		SignedLinkMiddleware(
			verifier: Ed25519PublicKeyring(key: privateKey.publicKey),
			maximumLifetime: maximumLifetime,
			dateProvider: clock.dateProvider,
		)
	}

	private func sign(expiresAt: Date) throws -> URL {
		try SignedLinkBuilder(signer: Ed25519LinkSigner(privateKey: privateKey))
			.sign(#require(URL(string: "https://example.com/invite")), expiresAt: expiresAt)
	}
}

#endif
