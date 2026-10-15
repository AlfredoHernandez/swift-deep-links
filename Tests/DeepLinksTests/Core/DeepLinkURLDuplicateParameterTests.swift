//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkURLDuplicateParameterTests {
	@Test
	func `duplicates are accepted by default and the last value wins`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&id=2"))

		let sut = try DeepLinkURL(url: url)

		#expect(sut.queryParameters == ["id": "2"])
		#expect(sut.allQueryParameters == ["id": ["1", "2"]])
	}

	@Test(arguments: [
		"myapp://product?id=1&id=2",
		"myapp://product?id=1&id",
		"myapp://product?flag&flag",
		"myapp://product?id=1&other=x&id=1",
	])
	func `rejecting duplicates throws invalidURL for a repeated key`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))

		#expect(throws: DeepLinkError.invalidURL(url)) {
			try DeepLinkURL(url: url, rejectDuplicateParameters: true)
		}
	}

	@Test
	func `rejecting duplicates accepts distinct keys`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&color=red&flag"))

		let sut = try DeepLinkURL(url: url, rejectDuplicateParameters: true)

		#expect(sut.queryParameters == ["id": "1", "color": "red"])
	}

	@Test
	func `rejecting duplicates treats keys case-sensitively`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&ID=2"))

		let sut = try DeepLinkURL(url: url, rejectDuplicateParameters: true)

		#expect(sut.queryParameters == ["id": "1", "ID": "2"])
	}

	@Test
	func `rejecting duplicates compares percent-decoded keys`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&%69d=2"))

		#expect(throws: DeepLinkError.invalidURL(url)) {
			try DeepLinkURL(url: url, rejectDuplicateParameters: true)
		}
	}

	@Test
	func `rejecting duplicates accepts a URL without a query`() throws {
		let url = try #require(URL(string: "myapp://product/42"))

		let sut = try DeepLinkURL(url: url, rejectDuplicateParameters: true)

		#expect(sut.queryParameters.isEmpty)
	}

	@Test
	func `rejecting duplicates ignores empty query segments`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&&"))

		let sut = try DeepLinkURL(url: url, rejectDuplicateParameters: true)

		#expect(sut.queryParameters == ["id": "1"])
	}

	@Test
	func `length check still applies when rejecting duplicates`() throws {
		let url = try #require(URL(string: "myapp://product?id=1"))

		#expect(throws: DeepLinkError.invalidURL(url)) {
			try DeepLinkURL(url: url, maxLength: 5, rejectDuplicateParameters: true)
		}
	}
}
