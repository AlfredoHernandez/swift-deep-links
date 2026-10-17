//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import Testing

struct SignedLinkParameterNamesTests {
	private let key = SymmetricKey(data: Data(repeating: 1, count: 32))
	private let clock = ManualDateProvider(now: Date(timeIntervalSince1970: 1_700_000_000))

	@Test
	func `the default names are distinctive`() {
		#expect(SignedLinkParameters.default == SignedLinkParameters(signature: "dlsig", expiry: "dlexp", nonce: "dlnonce", keyID: "dlkid"))
		#expect(SignedLinkParameters() == .default)
	}

	@Test
	func `the legacy names are the 2.0.0 names`() {
		#expect(SignedLinkParameters.legacy == SignedLinkParameters(signature: "sig", expiry: "exp", nonce: "nonce", keyID: "kid"))
	}

	@Test
	func `the builder appends the distinctive names by default`() throws {
		let signed = try SignedLinkBuilder(key: key, keyID: "2026")
			.sign(#require(URL(string: "https://example.com/reset?user=42")), expiresAt: Date(timeIntervalSince1970: 1_700_000_060), nonce: "n-1")

		#expect(signed.absoluteString.hasPrefix("https://example.com/reset?user=42&dlkid=2026&dlexp=1700000060&dlnonce=n-1&dlsig="))
	}

	@Test
	func `a link with an app parameter named sig is not taken for a signed link`() async throws {
		let link = try #require(URL(string: "https://example.com/photos?sig=landscape"))
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: key), requiredFor: .paths(["/reset"]), dateProvider: clock.dateProvider)

		let result = try await sut.intercept(DeepLinkRequest(url: link))

		#expect(result?.url == link)
		#expect(result?.context.isSignatureVerified == false)
	}

	@Test
	func `links minted with the legacy names verify with legacy names on both sides`() async throws {
		let signed = try SignedLinkBuilder(key: key, parameters: .legacy)
			.sign(#require(URL(string: "https://example.com/reset?user=42")), expiresAt: clock.now + 60)
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: key), parameters: .legacy, dateProvider: clock.dateProvider)

		let unsigned = try #require(URL(string: "https://example.com/reset?user=42"))

		let result = try await sut.intercept(DeepLinkRequest(url: signed))

		#expect(result?.url == unsigned)
		#expect(result?.context.isSignatureVerified == true)
	}

	@Test
	func `a legacy link is unsigned for a verifier using the default names`() async throws {
		let signed = try SignedLinkBuilder(key: key, parameters: .legacy)
			.sign(#require(URL(string: "https://example.com/reset?user=42")), expiresAt: clock.now + 60)
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: key), requiredFor: .paths(["/reset"]), dateProvider: clock.dateProvider)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: signed))
		}
	}

	@Test(arguments: ["dlsig", "dlnonce"])
	func `the default signature and nonce names are redacted`(name: String) {
		#expect(URLRedactor().isSensitive(parameterName: name))
	}
}

#endif
