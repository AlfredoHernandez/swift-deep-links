//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import os
import Testing

struct SignedLinkMiddlewareTests {
	// MARK: - Valid Links

	@Test
	func `signed link passes with the signature parameters removed`() async throws {
		let (sut, _) = makeSUT()
		let signed = try sign("https://example.com/reset?user=42")

		let result = try await sut.intercept(DeepLinkRequest(url: signed))

		#expect(result?.url == url("https://example.com/reset?user=42"))
	}

	@Test
	func `signature parameters are kept when stripping is disabled`() async throws {
		let (sut, _) = makeSUT(stripsSignatureParameters: false)
		let signed = try sign("https://example.com/reset?user=42")

		#expect(try await sut.intercept(DeepLinkRequest(url: signed))?.url == signed)
	}

	@Test
	func `request context is preserved and marked verified`() async throws {
		let (sut, _) = makeSUT()
		let context = DeepLinkContext(source: .universalLink, sceneID: "scene")
		var verified = context
		verified.isSignatureVerified = true

		let result = try await sut.intercept(DeepLinkRequest(url: sign("https://example.com/reset"), context: context))

		#expect(result?.context == verified)
	}

	@Test
	func `query order, scheme case and host case do not invalidate the signature`() async throws {
		let (sut, _) = makeSUT()
		let signed = try sign("https://example.com/reset?a=1&b=2").absoluteString
		let reordered = signed
			.replacingOccurrences(of: "https://example.com", with: "HTTPS://Example.COM")
			.replacingOccurrences(of: "a=1&b=2", with: "b=2&a=1")

		#expect(try await sut.intercept(DeepLinkRequest(url: url(reordered))) != nil)
	}

	@Test
	func `links outside the matcher pass unchanged without a signature`() async throws {
		let (sut, _) = makeSUT(requiredFor: .paths(["/reset"]))

		let result = try await sut.intercept(DeepLinkRequest(url: url("https://example.com/home?x=1")))

		#expect(result?.url == url("https://example.com/home?x=1"))
	}

	@Test(arguments: ["https://example.com/reset?user=42", "myapp://reset?user=42", "myapp://reset/42"])
	func `path rule requires a signature for web and custom-scheme spellings of the same link`(link: String) async throws {
		let (sut, _) = makeSUT(requiredFor: .paths(["/reset"]))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: url(link)))
		}
	}

	// MARK: - Tampering

	@Test(arguments: [
		("/reset", "/admin"),
		("user=42", "user=43"),
		("user=42", "user=42&role=admin"),
		("example.com", "evil.com"),
		("https", "myapp"),
	])
	func `tampered links are rejected`(original: String, replacement: String) async throws {
		let (sut, _) = makeSUT()
		let tampered = try sign("https://example.com/reset?user=42").absoluteString
			.replacingOccurrences(of: original, with: replacement)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: url(tampered)))
		}
	}

	@Test
	func `adding a fragment invalidates the signature`() async throws {
		let (sut, _) = makeSUT()
		let tampered = try sign("https://example.com/reset").absoluteString + "#admin"

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: url(tampered)))
		}
	}

	@Test
	func `missing signature is rejected`() async throws {
		let (sut, _) = makeSUT()

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: url("https://example.com/reset")))
		}
	}

	@Test(arguments: ["!!!", "", "a b"])
	func `malformed signature is rejected`(signature: String) async throws {
		let (sut, _) = makeSUT()
		let link = try #require(URLComponents(string: "https://example.com/reset")).with(query: [("sig", signature)])

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `duplicate signature parameter is rejected`() async throws {
		let (sut, _) = makeSUT()
		let signed = try sign("https://example.com/reset")
		let signature = try #require(queryValue("sig", in: signed))
		let duplicated = url(signed.absoluteString + "&sig=\(signature)")

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: duplicated))
		}
	}

	@Test
	func `duplicate expiry parameter is rejected`() async throws {
		let (sut, clock) = makeSUT()
		let signed = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)
		let duplicated = url(signed.absoluteString + "&exp=1")

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: duplicated))
		}
	}

	@Test
	func `failure reasons never contain the signature`() async throws {
		let (sut, _) = makeSUT()
		let tampered = try sign("https://example.com/reset?user=42").absoluteString.replacingOccurrences(of: "42", with: "43")
		let signature = try #require(queryValue("sig", in: url(tampered)))

		let error = await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(DeepLinkRequest(url: url(tampered)))
		}

		#expect(error?.errorDescription?.contains(signature) == false)
	}

	// MARK: - Keys

	@Test
	func `link signed with another key is rejected`() async throws {
		let (sut, _) = makeSUT()
		let forged = try SignedLinkBuilder(key: SymmetricKey(size: .bits256)).sign(url("https://example.com/reset"))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: forged))
		}
	}

	@Test
	func `rotated keys verify links signed with any listed key id`() async throws {
		let oldKey = SymmetricKey(data: Data(repeating: 2, count: 32))
		let newKey = SymmetricKey(data: Data(repeating: 3, count: 32))
		let (sut, _) = makeSUT(keys: SigningKeyring(keys: ["2025": oldKey, "2026": newKey]))

		let oldLink = try SignedLinkBuilder(key: oldKey, keyID: "2025").sign(url("https://example.com/reset"))
		let newLink = try SignedLinkBuilder(key: newKey, keyID: "2026").sign(url("https://example.com/reset"))

		#expect(try await sut.intercept(DeepLinkRequest(url: oldLink)) != nil)
		#expect(try await sut.intercept(DeepLinkRequest(url: newLink)) != nil)
	}

	@Test
	func `unknown key id is rejected like a bad signature`() async throws {
		let (sut, _) = makeSUT(keys: SigningKeyring(keys: ["2026": key]))
		let link = try SignedLinkBuilder(key: key, keyID: "retired").sign(url("https://example.com/reset"))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `link without key id is rejected by a keyring without a default key`() async throws {
		let (sut, _) = makeSUT(keys: SigningKeyring(keys: ["2026": key]))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: sign("https://example.com/reset")))
		}
	}

	@Test
	func `stripping the key id to fall back to the default key is rejected`() async throws {
		let otherKey = SymmetricKey(data: Data(repeating: 4, count: 32))
		let keyring = SigningKeyring(keys: ["default": key, "other": otherKey], defaultKeyID: "default")
		let (sut, _) = makeSUT(keys: keyring)
		let link = try SignedLinkBuilder(key: otherKey, keyID: "other").sign(url("https://example.com/reset"))
		let stripped = link.absoluteString.replacingOccurrences(of: "kid=other&", with: "")

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidSignatureReason)) {
			try await sut.intercept(DeepLinkRequest(url: url(stripped)))
		}
	}

	// MARK: - Expiry

	@Test
	func `link is valid until its expiry`() async throws {
		let (sut, clock) = makeSUT()
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)

		clock.advance(by: 59)

		#expect(try await sut.intercept(DeepLinkRequest(url: link)) != nil)
	}

	@Test
	func `link is rejected at and after its expiry`() async throws {
		let (sut, clock) = makeSUT()
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)

		clock.advance(by: 60)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.expiredReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `leeway tolerates clock skew after expiry`() async throws {
		let (sut, clock) = makeSUT(leeway: 30)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)

		clock.advance(by: 89)

		#expect(try await sut.intercept(DeepLinkRequest(url: link)) != nil)
	}

	@Test(arguments: [TimeInterval.infinity, -.infinity, .nan, -30])
	func `non-finite or negative leeway counts as zero`(leeway: TimeInterval) async throws {
		let (sut, clock) = makeSUT(leeway: leeway)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)

		clock.advance(by: 60)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.expiredReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `missing expiry is rejected when required`() async throws {
		let (sut, _) = makeSUT(requiresExpiry: true)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingExpiryReason)) {
			try await sut.intercept(DeepLinkRequest(url: sign("https://example.com/reset")))
		}
	}

	@Test
	func `malformed expiry is rejected even when signed`() async throws {
		let (sut, _) = makeSUT()
		let unsigned = try #require(URLComponents(string: "https://example.com/reset")).with(query: [("exp", "soon")])
		let signature = SignedLinkCanonicalForm.signature(of: unsigned, parameters: .default, using: key)
		let link = try #require(URLComponents(url: unsigned, resolvingAgainstBaseURL: false)).with(query: [("exp", "soon"), ("sig", signature)])

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.invalidExpiryReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	// MARK: - Nonces

	@Test
	func `nonce is accepted once`() async throws {
		let clock = ManualDateProvider()
		let (sut, _) = makeSUT(nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider), clock: clock)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60, nonce: "n-1")

		#expect(try await sut.intercept(DeepLinkRequest(url: link)) != nil)
		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.reusedNonceReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `reused nonce can be dropped quietly`() async throws {
		let clock = ManualDateProvider()
		let sut = SignedLinkMiddleware(
			keys: SigningKeyring(key: key),
			nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider),
			reusedNonce: .drop,
			dateProvider: clock.dateProvider,
		)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60, nonce: "n-1")

		#expect(try await sut.intercept(DeepLinkRequest(url: link)) != nil)
		#expect(try await sut.intercept(DeepLinkRequest(url: link)) == nil)
	}

	@Test
	func `duplicate delivery is dropped by replay protection placed before signed links`() async throws {
		let clock = ManualDateProvider()
		let chain = DeepLinkMiddlewareCoordinator(middleware: [
			ReplayProtectionMiddleware(window: 2, dateProvider: clock.dateProvider),
			SignedLinkMiddleware(
				keys: SigningKeyring(key: key),
				nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider),
				dateProvider: clock.dateProvider,
			),
		])
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60, nonce: "n-1")

		#expect(try await chain.process(DeepLinkRequest(url: link)) != nil)
		#expect(try await chain.process(DeepLinkRequest(url: link)) == nil)
	}

	@Test
	func `concurrent deliveries of one nonce admit exactly one`() async throws {
		let clock = ManualDateProvider()
		let (sut, _) = makeSUT(nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider), clock: clock)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60, nonce: "n-1")

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 50 {
				group.addTask { await (try? sut.intercept(DeepLinkRequest(url: link))) != nil }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 1)
	}

	@Test
	func `forged link does not consume the nonce`() async throws {
		let clock = ManualDateProvider()
		let (sut, _) = makeSUT(nonceStore: InMemoryNonceStore(dateProvider: clock.dateProvider), clock: clock)
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60, nonce: "n-1")
		let forged = url(link.absoluteString.replacingOccurrences(of: "/reset", with: "/admin"))

		_ = try? await sut.intercept(DeepLinkRequest(url: forged))

		#expect(try await sut.intercept(DeepLinkRequest(url: link)) != nil)
	}

	@Test
	func `missing nonce is rejected when a nonce store is configured`() async throws {
		let (sut, clock) = makeSUT(nonceStore: InMemoryNonceStore())
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: clock.now + 60)

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingNonceReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `nonce store requires an expiry even when expiry is optional`() async throws {
		let (sut, _) = makeSUT(requiresExpiry: false, nonceStore: InMemoryNonceStore())
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), nonce: "n-1")

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.missingExpiryReason)) {
			try await sut.intercept(DeepLinkRequest(url: link))
		}
	}

	@Test
	func `nonce is retained until the link expires`() async throws {
		let nonces = RecordingNonceStore()
		let (sut, clock) = makeSUT(nonceStore: nonces)
		let expiry = clock.now + 60
		let link = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset"), expiresAt: expiry, nonce: "n-1")

		_ = try await sut.intercept(DeepLinkRequest(url: link))

		#expect(nonces.consumed == [RecordingNonceStore.Entry(nonce: "n-1", expiresAt: expiry)])
	}

	// MARK: - Factory

	@Test
	func `factory builds a working middleware`() async throws {
		let clock = ManualDateProvider()
		let sut: SignedLinkMiddleware = .signedLinks(
			keys: SigningKeyring(key: key),
			requiredFor: .hosts(["example.com"]),
			requiresExpiry: false,
			dateProvider: clock.dateProvider,
		)

		#expect(try await sut.intercept(DeepLinkRequest(url: sign("https://example.com/reset"))) != nil)
		await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(DeepLinkRequest(url: url("https://example.com/reset")))
		}
	}
}

// MARK: - Helpers

private let key = SymmetricKey(data: Data(repeating: 1, count: 32))

private func makeSUT(
	keys: any SigningKeyProvider = SigningKeyring(key: key),
	requiredFor matcher: DeepLinkMatcher = .all,
	requiresExpiry: Bool = false,
	leeway: TimeInterval = 0,
	nonceStore: (any NonceStore)? = nil,
	stripsSignatureParameters: Bool = true,
	clock: ManualDateProvider = ManualDateProvider(),
) -> (SignedLinkMiddleware, ManualDateProvider) {
	let sut = SignedLinkMiddleware(
		keys: keys,
		requiredFor: matcher,
		requiresExpiry: requiresExpiry,
		leeway: leeway,
		nonceStore: nonceStore,
		stripsSignatureParameters: stripsSignatureParameters,
		dateProvider: clock.dateProvider,
	)
	return (sut, clock)
}

private func sign(_ string: String) throws -> URL {
	try SignedLinkBuilder(key: key).sign(url(string))
}

private func queryValue(_ name: String, in url: URL) -> String? {
	URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

private func url(_ string: String) -> URL {
	URL(string: string)!
}

private extension URLComponents {
	func with(query items: [(String, String)]) -> URL {
		var copy = self
		copy.queryItems = (queryItems ?? []).filter { existing in !items.contains { $0.0 == existing.name } }
			+ items.map { URLQueryItem(name: $0.0, value: $0.1) }
		return copy.url!
	}
}

private final class RecordingNonceStore: NonceStore {
	struct Entry: Equatable {
		let nonce: String
		let expiresAt: Date
	}

	private let entries = OSAllocatedUnfairLock<[Entry]>(initialState: [])

	var consumed: [Entry] {
		entries.withLock { $0 }
	}

	func consume(_ nonce: String, expiresAt: Date) async -> Bool {
		entries.withLock { $0.append(Entry(nonce: nonce, expiresAt: expiresAt)) }
		return true
	}
}

#endif
