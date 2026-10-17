//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import Foundation
import Testing

struct SignedLinkDuplicateParameterTests {
	@Test
	func `swapping the values of a repeated parameter does not keep a valid signature`() async throws {
		let signed = try SignedLinkBuilder(key: key, rejectDuplicateParameters: false)
			.sign(url("https://example.com/reset?user=1&user=2"))
		let swapped = url(signed.absoluteString.replacingOccurrences(of: "user=1&user=2", with: "user=2&user=1"))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.duplicateParameterReason)) {
			try await SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false, maximumLifetime: nil)
				.intercept(DeepLinkRequest(url: swapped))
		}
	}

	@Test(arguments: [
		"https://example.com/reset?user=1&user=2",
		"https://example.com/reset?us%65r=1&user=2",
		"https://example.com/reset?flag&flag",
		"https://example.com/reset?flag&flag=1",
	])
	func `a signed link repeating a decoded parameter name is rejected`(link: String) async throws {
		let signed = try SignedLinkBuilder(key: key, rejectDuplicateParameters: false).sign(url(link))

		await #expect(throws: DeepLinkError.securityViolation(SignedLinkMiddleware.duplicateParameterReason)) {
			try await SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false, maximumLifetime: nil)
				.intercept(DeepLinkRequest(url: signed))
		}
	}

	@Test
	func `a verifier that opts out accepts a signed link repeating a parameter`() async throws {
		let signed = try SignedLinkBuilder(key: key, rejectDuplicateParameters: false)
			.sign(url("https://example.com/reset?tag=a&tag=b"))
		let sut = SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false, maximumLifetime: nil, rejectDuplicateParameters: false)

		#expect(try await sut.intercept(DeepLinkRequest(url: signed))?.url == url("https://example.com/reset?tag=a&tag=b"))
	}

	@Test
	func `distinct parameter names still verify`() async throws {
		let signed = try SignedLinkBuilder(key: key).sign(url("https://example.com/reset?user=1&team=2"))

		let result = try await SignedLinkMiddleware(keys: SigningKeyring(key: key), requiresExpiry: false, maximumLifetime: nil)
			.intercept(DeepLinkRequest(url: signed))

		#expect(result?.url == url("https://example.com/reset?user=1&team=2"))
	}

	@Test
	func `the builder refuses to sign a link repeating a parameter`() throws {
		#expect(throws: DeepLinkError.invalidURL(url("https://example.com/reset?user=1&user=2"))) {
			try SignedLinkBuilder(key: key).sign(url("https://example.com/reset?user=1&user=2"))
		}
	}

	@Test
	func `the duplicate reason maps to the duplicate parameter case`() {
		#expect(DeepLinkError.securityViolation(SignedLinkMiddleware.duplicateParameterReason).securityViolationReason == .duplicateParameter)
	}
}

private let key = SymmetricKey(data: Data(repeating: 7, count: 32))

private func url(_ string: String) -> URL {
	URL(string: string)!
}

#endif
