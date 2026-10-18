//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkParserFactoryTests {
	// MARK: - Multi-route overload

	@Test
	func `from multi-route overload forwards the closure's array result`() async throws {
		let url = try #require(URL(string: "test://multi"))
		let parser: any DeepLinkParser<TestRoute> = .from { _ in
			[.route1, .route2]
		}

		let routes = try await parser.parse(from: url)

		#expect(routes == [.route1, .route2])
	}

	@Test
	func `from multi-route overload returns an empty array when the closure produces none`() async throws {
		let url = try #require(URL(string: "test://empty"))
		let parser: any DeepLinkParser<TestRoute> = .from { _ in [] as [TestRoute] }

		let routes = try await parser.parse(from: url)

		#expect(routes.isEmpty)
	}

	@Test
	func `from multi-route overload forwards the exact error thrown from the closure`() async throws {
		let url = try #require(URL(string: "test://multi-error"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> [TestRoute] in
			throw DeepLinkError.invalidURL(url)
		}

		await #expect(throws: DeepLinkError.invalidURL(url)) {
			try await parser.parse(from: url)
		}
	}

	// MARK: - Single-route overload

	@Test
	func `from single-route overload wraps non-nil result in a one-element array`() async throws {
		let url = try #require(URL(string: "test://single"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> TestRoute? in
			.route1
		}

		let routes = try await parser.parse(from: url)

		#expect(routes == [.route1])
	}

	@Test
	func `from single-route overload throws routeNotFound when closure returns nil`() async throws {
		let url = try #require(URL(string: "test://nothing"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> TestRoute? in
			nil
		}

		await #expect(throws: DeepLinkError.routeNotFound(url)) {
			try await parser.parse(from: url)
		}
	}

	@Test
	func `from single-route overload surfaces the full URL when it has no host`() async throws {
		let url = try #require(URL(string: "test:///"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> TestRoute? in
			nil
		}

		await #expect(throws: DeepLinkError.routeNotFound(url)) {
			try await parser.parse(from: url)
		}
	}

	@Test
	func `from single-route overload surfaces the full URL when the URL has no authority component`() async throws {
		let url = try #require(URL(string: "test://"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> TestRoute? in
			nil
		}

		await #expect(throws: DeepLinkError.routeNotFound(url)) {
			try await parser.parse(from: url)
		}
	}

	@Test
	func `from single-route overload forwards the exact error thrown from the closure`() async throws {
		let url = try #require(URL(string: "test://single-error"))
		let parser: any DeepLinkParser<TestRoute> = .from { (_: URL) -> TestRoute? in
			throw DeepLinkError.missingRequiredParameter("id")
		}

		await #expect(throws: DeepLinkError.missingRequiredParameter("id")) {
			try await parser.parse(from: url)
		}
	}
}
