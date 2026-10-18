//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkResultFirstDeepLinkErrorTests {
	@Test
	func `returns nil when errors is empty`() throws {
		let result = try DeepLinkResult<StubRoute>(
			originalURL: #require(URL(string: "app://home")),
			processedURL: #require(URL(string: "app://home")),
			routes: [],
			executionTime: 0,
		)

		#expect(result.firstDeepLinkError == nil)
	}

	@Test
	func `returns first DeepLinkError when it is the only error`() throws {
		let expected = DeepLinkError.unsupportedScheme("ftp")
		let result = try DeepLinkResult<StubRoute>(
			originalURL: #require(URL(string: "app://home")),
			processedURL: nil,
			routes: [],
			executionTime: 0,
			errors: [expected],
		)

		#expect(result.firstDeepLinkError == expected)
	}

	@Test
	func `skips non-DeepLinkError entries to find the first DeepLinkError`() throws {
		let expected = DeepLinkError.missingRequiredParameter("userId")
		let nonFrameworkError = NSError(domain: "OtherDomain", code: 42)
		let result = try DeepLinkResult<StubRoute>(
			originalURL: #require(URL(string: "app://profile")),
			processedURL: #require(URL(string: "app://profile")),
			routes: [],
			executionTime: 0,
			errors: [nonFrameworkError, expected],
		)

		#expect(result.firstDeepLinkError == expected)
	}

	@Test
	func `returns first DeepLinkError from mixed error chain`() throws {
		let first = DeepLinkError.unsupportedHost("unknown")
		let second = DeepLinkError.missingRequiredParameter("id")
		let other = NSError(domain: "OtherDomain", code: 1)
		let result = try DeepLinkResult<StubRoute>(
			originalURL: #require(URL(string: "app://x")),
			processedURL: #require(URL(string: "app://x")),
			routes: [],
			executionTime: 0,
			errors: [other, first, second],
		)

		#expect(result.firstDeepLinkError == first)
	}

	@Test
	func `returns nil when errors contains only non-DeepLinkError entries`() throws {
		let result = try DeepLinkResult<StubRoute>(
			originalURL: #require(URL(string: "app://x")),
			processedURL: #require(URL(string: "app://x")),
			routes: [],
			executionTime: 0,
			errors: [NSError(domain: "A", code: 1), NSError(domain: "B", code: 2)],
		)

		#expect(result.firstDeepLinkError == nil)
	}

	private struct StubRoute: DeepLinkRoute {
		let id: String = "stub"
	}
}
