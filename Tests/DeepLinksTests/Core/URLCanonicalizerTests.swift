//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct URLCanonicalizerTests {
	private let sut = URLCanonicalizer()

	@Test
	func `canonicalize lower-cases scheme and host and preserves path and query`() throws {
		let url = try #require(URL(string: "MyApp://Example.COM/Products/ABC?Ref=XyZ"))

		let canonical = try sut.canonicalize(url)

		#expect(canonical.absoluteString == "myapp://example.com/Products/ABC?Ref=XyZ")
	}

	@Test
	func `canonicalize returns an already canonical URL unchanged`() throws {
		let url = try #require(URL(string: "https://example.com/a/b?c=d#e"))

		#expect(try sut.canonicalize(url) == url)
	}

	@Test(arguments: [
		"https://allowed.com@evil.com/path",
		"https://user:secret@example.com/path",
		"myapp://user@home",
		"https://trusted.com\\@evil.com",
	])
	func `canonicalize rejects URLs carrying userinfo`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Userinfo is not allowed")) {
			try sut.canonicalize(url)
		}
	}

	@Test(arguments: [
		"myapp://home/path%00",
		"myapp://home/path?q=a%0Ab",
		"myapp://home/%7F",
		"myapp://home/%C2%85",
		"myapp://home/path?q=%250A",
		"myapp://home/path?q=%250A%25zz",
	])
	func `canonicalize rejects percent-encoded control characters`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Control characters are not allowed")) {
			try sut.canonicalize(url)
		}
	}

	@Test(arguments: [
		"myapp://home/invoice%E2%80%AEfdp.exe",
		"myapp://home/path?q=a%E2%80%A8b",
		"myapp://home/path?q=a%E2%80%A9b",
		"myapp://home/ad%E2%80%8Bmin",
		"myapp://home/path?q=%EF%BB%BF",
		"myapp://home/path?q=%25E2%2580%25AE",
		"myapp://home/invoice\u{202E}fdp",
		"myapp://home/ad\u{200B}min",
	])
	func `canonicalize rejects invisible format and separator characters`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Invisible formatting characters are not allowed")) {
			try sut.canonicalize(url)
		}
	}

	@Test
	func `canonicalize keeps visible non-ASCII text`() throws {
		let url = try #require(URL(string: "myapp://home/search?q=caf%C3%A9"))

		#expect(try sut.canonicalize(url) == url)
	}

	@Test(arguments: [
		"myapp://home/a/../admin",
		"myapp://home/..",
		"myapp://home/a/%2e%2e/admin",
		"myapp://home/a/%2E%2e/admin",
		"myapp://home/a/.%2E/admin",
		"myapp://home/a/%252e%252e/admin",
		"myapp://home/a/%2e%2e%2fadmin",
		"myapp://home/a/..%5Cadmin",
		"myapp://home/%252e%252e/%25zz",
		"myapp://home/a/..;/admin",
		"myapp://home/.%2e;x/admin",
		"myapp://home/a/..;jsessionid=1/admin",
		"myapp://home/a/%2e%2e%3B/admin",
		"myapp://home/a%5C..;x%5Cadmin",
		"myapp://home/a/%EF%BC%8E%EF%BC%8E/admin",
		"myapp://home/a/.%EF%BC%8E/admin",
		"myapp://home/a/%EF%BC%8E/admin",
		"myapp://home/a/%E3%80%82%E3%80%82/admin",
		"myapp://home/a/%EF%BD%A1%EF%BD%A1/admin",
		"myapp://home/a/%25EF%25BC%258E%25EF%25BC%258E/admin",
		"myapp://home/a/%EF%BC%8E%EF%BC%8E;x/admin",
	])
	func `canonicalize rejects dot-dot path segments in raw and encoded forms`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Path traversal is not allowed")) {
			try sut.canonicalize(url)
		}
	}

	@Test(arguments: [
		"myapp://home/a..b",
		"myapp://home/.hidden",
		"myapp://home/./a",
		"myapp://home/a?next=../b",
		"myapp://home/a;v=1/b",
		"myapp://home/.;x/b",
		"myapp://home/v1%EF%BC%8E2",
		"myapp://home/a?next=%EF%BC%8E%EF%BC%8E/b",
	])
	func `canonicalize accepts dots that are not dot-dot path segments`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: Never.self) {
			try sut.canonicalize(url)
		}
	}

	@Test
	func `canonicalize rejects percent-encoding that is not valid UTF-8`() throws {
		let url = try #require(URL(string: "myapp://home/%C0%AE%C0%AE/admin"))

		#expect(throws: DeepLinkError.securityViolation("Malformed percent-encoding")) {
			try sut.canonicalize(url)
		}
	}

	@Test
	func `canonicalize rejects percent-encoding nested deeper than the decoding limit`() throws {
		let url = try #require(URL(string: "myapp://home/%2525252541"))

		#expect(throws: DeepLinkError.securityViolation("Malformed percent-encoding")) {
			try sut.canonicalize(url)
		}
	}

	@Test
	func `canonicalize accepts an encoded literal percent sign`() throws {
		let url = try #require(URL(string: "myapp://home/deals?code=100%25off"))

		#expect(try sut.canonicalize(url) == url)
	}

	@Test
	func `matchable forms include the raw string and every percent-decoding pass`() throws {
		let url = try #require(URL(string: "myapp://home/%256A%61vascript"))

		let forms = sut.matchableForms(of: url)

		#expect(forms == [
			"myapp://home/%256A%61vascript",
			"myapp://home/%6Aavascript",
			"myapp://home/javascript",
		])
	}

	@Test
	func `matchable forms keep decoding past an invalid escape left from a literal percent sign`() throws {
		let url = try #require(URL(string: "myapp://home/%256A%61vascript%25zz"))

		let forms = sut.matchableForms(of: url)

		#expect(forms.last == "myapp://home/javascript%zz")
	}

	@Test
	func `matchable forms of a URL without encoding contain only the raw string`() throws {
		let url = try #require(URL(string: "myapp://home/path"))

		#expect(sut.matchableForms(of: url) == ["myapp://home/path"])
	}

	@Test(arguments: [
		("myapp://account./x", "myapp://account/x"),
		("https://Example.com./a", "https://example.com/a"),
		("myapp://account%2e/x", "myapp://account/x"),
		("myapp://%61CCOUNT/x", "myapp://account/x"),
	])
	func `canonicalize decodes the host and drops its trailing dot`(rawURL: String, expected: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(try sut.canonicalize(url).absoluteString == expected)
	}

	@Test(arguments: ["myapp://acc%2Fount/x", "myapp://acc%3Fount", "myapp://acc%40evil/x", "myapp://acc%25ount"])
	func `canonicalize rejects a host that decodes to a delimiter`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.securityViolation("Malformed host")) {
			try sut.canonicalize(url)
		}
	}
}
