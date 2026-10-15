//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import Foundation
import Testing

struct SignedLinkBuilderTests {
	@Test
	func `canonical form is the documented newline-separated string`() throws {
		let link = try #require(URL(string: "HTTPS://Example.COM:8443/a/%7euser/b%2fc?z=1&a=%41&flag#Frag"))

		let canonical = SignedLinkCanonicalForm.string(of: link, parameters: .default)

		#expect(canonical == "DLSIG1\nhttps\nexample.com\n8443\n/a/~user/b%2Fc\na=A&flag&z=1\nFrag")
	}

	@Test
	func `canonical form does not cover userinfo`() throws {
		let plain = try #require(URL(string: "https://example.com/reset"))
		let withUserinfo = try #require(URL(string: "https://user:pass@example.com/reset"))

		#expect(SignedLinkCanonicalForm.string(of: withUserinfo, parameters: .default)
			== SignedLinkCanonicalForm.string(of: plain, parameters: .default))
	}

	@Test
	func `canonical form excludes only the signature parameter`() throws {
		let link = try #require(URL(string: "myapp://reset?kid=k&exp=10&nonce=n&sig=abc"))

		#expect(SignedLinkCanonicalForm.string(of: link, parameters: .default) == "DLSIG1\nmyapp\nreset\n\n\nexp=10&kid=k&nonce=n\n")
	}

	@Test
	func `signature is the unpadded base64url HMAC-SHA256 of the canonical form`() throws {
		let key = SymmetricKey(data: Data(repeating: 1, count: 32))
		let link = try #require(URL(string: "myapp://reset?user=42"))
		let expected = Data(HMAC<SHA256>.authenticationCode(for: Data("DLSIG1\nmyapp\nreset\n\n\nuser=42\n".utf8), using: key))
			.base64EncodedString()
			.replacingOccurrences(of: "+", with: "-")
			.replacingOccurrences(of: "/", with: "_")
			.replacingOccurrences(of: "=", with: "")

		let signed = try SignedLinkBuilder(key: key).sign(link)

		#expect(signed.absoluteString == "myapp://reset?user=42&sig=\(expected)")
	}

	@Test
	func `signature matches the pinned reference vector`() throws {
		let key = SymmetricKey(data: Data(repeating: 1, count: 32))
		let link = try #require(URL(string: "https://example.com/reset?user=42"))

		let signed = try SignedLinkBuilder(key: key, keyID: "2026").sign(
			link,
			expiresAt: Date(timeIntervalSince1970: 1_700_000_060),
			nonce: "n-1",
		)

		#expect(signed.absoluteString
			== "https://example.com/reset?user=42&kid=2026&exp=1700000060&nonce=n-1&sig=1OAKGbiJ5WvCYwvoLez3vNDV8PDLx1PRzNZeIwKsXEc")
	}

	@Test
	func `builder appends key id, expiry and nonce before the signature`() throws {
		let key = SymmetricKey(data: Data(repeating: 1, count: 32))
		let link = try #require(URL(string: "myapp://reset?user=42"))

		let signed = try SignedLinkBuilder(key: key, keyID: "2026").sign(
			link,
			expiresAt: Date(timeIntervalSince1970: 1_700_000_060.9),
			nonce: "a b",
		)

		#expect(signed.absoluteString.hasPrefix("myapp://reset?user=42&kid=2026&exp=1700000060&nonce=a%20b&sig="))
	}

	@Test(arguments: ["sig", "exp", "kid", "nonce"])
	func `builder rejects URLs that already carry a reserved parameter`(name: String) throws {
		let key = SymmetricKey(data: Data(repeating: 1, count: 32))
		let link = try #require(URL(string: "myapp://reset?\(name)=1"))

		#expect(throws: DeepLinkError.invalidURL(link)) {
			try SignedLinkBuilder(key: key).sign(link)
		}
	}

	@Test
	func `custom parameter names are used by builder and canonical form`() throws {
		let key = SymmetricKey(data: Data(repeating: 1, count: 32))
		let parameters = SignedLinkParameters(signature: "s", expiry: "e", nonce: "n", keyID: "k")
		let link = try #require(URL(string: "myapp://reset"))

		let signed = try SignedLinkBuilder(key: key, keyID: "1", parameters: parameters).sign(link, expiresAt: Date(timeIntervalSince1970: 5), nonce: "x")

		#expect(signed.absoluteString.hasPrefix("myapp://reset?k=1&e=5&n=x&s="))
	}
}

#endif
