//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct ConfigurationHardeningTests {
	// MARK: - Security Policy

	@Test
	func `blocked patterns are recompiled case-insensitively once, when the policy is built`() throws {
		let policy = try SecurityPolicy(allowedSchemes: ["myapp"], blockedPatterns: [NSRegularExpression(pattern: "javascript:")])

		let compiled = try policy.caseInsensitiveBlockedPatterns.get()

		#expect(compiled.map(\.pattern) == ["javascript:"])
		#expect(compiled.allSatisfy { $0.options.contains(.caseInsensitive) })
	}

	@Test
	func `allow-lists are normalized when the policy is built`() {
		let policy = SecurityPolicy(
			allowedSchemes: ["MyApp"],
			allowedHosts: ["Example.COM."],
			allowedHostsByScheme: ["HTTPS": ["Pay.Example.com"]],
		)

		#expect(policy.normalizedSchemes == ["myapp"])
		#expect(policy.normalizedHosts == ["example.com"])
		#expect(policy.normalizedHosts(forScheme: "https") == ["pay.example.com"])
	}

	@Test
	func `hardened accepts an allowed host listed with a trailing dot`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["https"], allowedHosts: ["Example.COM."])
		let url = try #require(URL(string: "https://example.com/a"))

		#expect(try await sut.intercept(url: url) == url)
	}

	// MARK: - Shared Rate-Limit Persistence

	@Test
	func `default rate limiters share one persistence per key`() throws {
		let first = try #require((RateLimitMiddleware.rateLimit() as RateLimitMiddleware).persistence as? UserDefaultsRateLimitPersistence)
		let second = try #require(RateLimitMiddleware().persistence as? UserDefaultsRateLimitPersistence)
		let otherKey = UserDefaultsRateLimitPersistence.shared(key: "test.config-hardening.other")

		#expect(first === second)
		#expect(otherKey === UserDefaultsRateLimitPersistence.shared(key: "test.config-hardening.other"))
		#expect(otherKey !== first)
	}
}

#if canImport(CryptoKit)

import CryptoKit

extension ConfigurationHardeningTests {
	// MARK: - Signed Links Without a Nonce Store

	@Test
	func `diagnostics warn about signed links without a nonce store`() {
		let keys = Ed25519PublicKeyring(key: Curve25519.Signing.PrivateKey().publicKey)
		let sut = DeepLinkDiagnostics(declaredURLSchemes: [])

		let warnings = sut.checkMiddleware([.signedLinks(verifier: keys), .logging()])
		let withStore = sut.checkMiddleware([.signedLinks(verifier: keys, nonceStore: InMemoryNonceStore())])

		#expect(warnings == [.signedLinksWithoutNonceStore])
		#expect(withStore.isEmpty)
		#expect(DeepLinkDiagnosticWarning.signedLinksWithoutNonceStore.description.contains("nonce"))
	}
}

#endif
