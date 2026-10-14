//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkInputLimitsTests {
	@Test
	func `unlimited accepts an oversized URL with many long parameters`() throws {
		let url = try makeURL(queryCount: 500, valueLength: 5000)

		try DeepLinkInputLimits.unlimited.validate(url)
	}

	@Test
	func `validate accepts a URL exactly at the maximum length`() throws {
		let url = try #require(URL(string: "myapp://home/12345"))
		let sut = DeepLinkInputLimits(maxURLLength: url.absoluteString.count)

		try sut.validate(url)
	}

	@Test
	func `validate rejects a URL one character over the maximum length`() throws {
		let url = try #require(URL(string: "myapp://home/12345"))
		let sut = DeepLinkInputLimits(maxURLLength: url.absoluteString.count - 1)

		#expect(throws: DeepLinkError.securityViolation("URL exceeds maximum length")) {
			try sut.validate(url)
		}
	}

	@Test
	func `validate accepts exactly the maximum number of query parameters`() throws {
		let url = try makeURL(queryCount: 3, valueLength: 1)
		let sut = DeepLinkInputLimits(maxQueryParameterCount: 3)

		try sut.validate(url)
	}

	@Test
	func `validate rejects more query parameters than allowed`() throws {
		let url = try makeURL(queryCount: 4, valueLength: 1)
		let sut = DeepLinkInputLimits(maxQueryParameterCount: 3)

		#expect(throws: DeepLinkError.securityViolation("Too many query parameters")) {
			try sut.validate(url)
		}
	}

	@Test
	func `validate counts duplicate and valueless parameters`() throws {
		let url = try #require(URL(string: "myapp://home?a=1&a=2&flag"))
		let sut = DeepLinkInputLimits(maxQueryParameterCount: 2)

		#expect(throws: DeepLinkError.securityViolation("Too many query parameters")) {
			try sut.validate(url)
		}
	}

	@Test
	func `validate ignores empty query segments when counting parameters`() throws {
		let url = try #require(URL(string: "myapp://home?a=1&&&b=2&"))
		let sut = DeepLinkInputLimits(maxQueryParameterCount: 2)

		try sut.validate(url)
	}

	@Test
	func `validate accepts a URL without a query when parameters are capped at zero`() throws {
		let url = try #require(URL(string: "myapp://home/path"))
		let sut = DeepLinkInputLimits(maxQueryParameterCount: 0)

		try sut.validate(url)
	}

	@Test
	func `validate accepts a parameter value exactly at the maximum length`() throws {
		let url = try makeURL(queryCount: 1, valueLength: 8)
		let sut = DeepLinkInputLimits(maxParameterValueLength: 8)

		try sut.validate(url)
	}

	@Test
	func `validate rejects a parameter value over the maximum length`() throws {
		let url = try makeURL(queryCount: 1, valueLength: 9)
		let sut = DeepLinkInputLimits(maxParameterValueLength: 8)

		#expect(throws: DeepLinkError.securityViolation("Query parameter value exceeds maximum length")) {
			try sut.validate(url)
		}
	}

	@Test
	func `validate measures the percent-decoded parameter value`() throws {
		let url = try #require(URL(string: "myapp://home?name=%41%42%43"))
		let sut = DeepLinkInputLimits(maxParameterValueLength: 3)

		try sut.validate(url)
	}

	@Test
	func `negative limits are clamped to zero`() {
		let sut = DeepLinkInputLimits(maxURLLength: -5, maxQueryParameterCount: -1, maxParameterValueLength: -3)

		#expect(sut.maxURLLength == 0)
		#expect(sut.maxQueryParameterCount == 0)
		#expect(sut.maxParameterValueLength == 0)
	}

	@Test
	func `recommended caps length at the DeepLinkURL default`() {
		#expect(DeepLinkInputLimits.recommended.maxURLLength == DeepLinkURL.defaultMaxLength)
		#expect(DeepLinkInputLimits.recommended.maxQueryParameterCount != nil)
		#expect(DeepLinkInputLimits.recommended.maxParameterValueLength != nil)
	}

	@Test
	func `canonicalizer with limits rejects an oversized URL before any structural check`() throws {
		let url = try #require(URL(string: "https://user@example.com/\(String(repeating: "a", count: 64))"))
		let sut = URLCanonicalizer(limits: DeepLinkInputLimits(maxURLLength: 32))

		#expect(throws: DeepLinkError.securityViolation("URL exceeds maximum length")) {
			try sut.canonicalize(url)
		}
	}

	@Test
	func `canonicalizer without limits keeps accepting long URLs`() throws {
		let url = try makeURL(queryCount: 200, valueLength: 100)

		_ = try URLCanonicalizer().canonicalize(url)
	}

	private func makeURL(queryCount: Int, valueLength: Int) throws -> URL {
		let value = String(repeating: "v", count: valueLength)
		let query = (0 ..< queryCount).map { "p\($0)=\(value)" }.joined(separator: "&")
		return try #require(URL(string: "myapp://home/path?\(query)"))
	}
}
