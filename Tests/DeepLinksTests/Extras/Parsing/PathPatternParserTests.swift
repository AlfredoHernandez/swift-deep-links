//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct PathPatternParserTests {
	// MARK: - Matching

	@Test
	func `literal and capture segments produce the built route`() async throws {
		let sut = try productParser()

		let routes = try await sut.parse(from: url("https://shop.example.com/products/42"))

		#expect(routes == [.product(id: 42)])
	}

	@Test
	func `trailing slash and repeated slashes still match`() async throws {
		let sut = try productParser()

		#expect(try await sut.parse(from: url("https://shop.example.com/products/42/")) == [.product(id: 42)])
		#expect(try await sut.parse(from: url("https://shop.example.com//products//42")) == [.product(id: 42)])
	}

	@Test(arguments: [
		"https://shop.example.com/products",
		"https://shop.example.com/products/42/reviews",
		"https://shop.example.com/Products/42",
		"https://shop.example.com/items/42",
		"https://shop.example.com/",
	])
	func `structural mismatch throws route not found`(string: String) async throws {
		let sut = try productParser()

		await #expect(throws: DeepLinkError.routeNotFound(url(string))) {
			try await sut.parse(from: url(string))
		}
	}

	@Test
	func `wildcard captures the remaining segments`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/u/:handle/posts/*") { match in
			try .posts(handle: match.string("handle"), rest: match.wildcard)
		}

		let routes = try await sut.parse(from: url("https://example.com/u/ana/posts/2024/hello"))

		#expect(routes == [.posts(handle: "ana", rest: ["2024", "hello"])])
	}

	@Test
	func `wildcard matches zero remaining segments`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/u/:handle/posts/*") { match in
			try .posts(handle: match.string("handle"), rest: match.wildcard)
		}

		#expect(try await sut.parse(from: url("https://example.com/u/ana/posts")) == [.posts(handle: "ana", rest: [])])
	}

	@Test
	func `root template matches only the empty path`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/") { _ in .home }

		#expect(try await sut.parse(from: url("https://example.com")) == [.home])
		#expect(try await sut.parse(from: url("https://example.com/")) == [.home])
		await #expect(throws: DeepLinkError.self) { try await sut.parse(from: url("https://example.com/a")) }
	}

	@Test
	func `host and path scope treats the custom scheme host as the first segment`() async throws {
		let sut = try PathPatternParser<PatternRoute>("products/:id", scope: .hostAndPath) { match in
			try .product(id: match.int("id"))
		}

		#expect(try await sut.parse(from: url("myapp://Products/7")) == [.product(id: 7)])
	}

	@Test
	func `host filter compares case-insensitively and rejects other hosts`() async throws {
		let sut = try productParser(hosts: ["Shop.Example.com"])

		#expect(try await sut.parse(from: url("https://shop.example.COM/products/1")) == [.product(id: 1)])
		await #expect(throws: DeepLinkError.routeNotFound(url("https://evil.com/products/1"))) {
			try await sut.parse(from: url("https://evil.com/products/1"))
		}
	}

	@Test
	func `match exposes the original URL for query access`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/search") { match in
			try .search(query: DeepLinkURL(url: match.url).queryParameters["q"] ?? "")
		}

		#expect(try await sut.parse(from: url("https://example.com/search?q=shoes")) == [.search(query: "shoes")])
	}

	// MARK: - Typed Captures

	@Test(arguments: ["-5", "+5", "007", "00", "-0"])
	func `int rejects signs and leading zeros`(value: String) async throws {
		let sut = try PathPatternParser<PatternRoute>(
			"/products/:id",
			allowedCharacters: PathPatternParser<PatternRoute>.defaultAllowedCharacters.union(CharacterSet(charactersIn: "+")),
		) { match in
			try .product(id: match.int("id"))
		}

		await #expect(throws: DeepLinkError.invalidParameterValue(name: "id", value: value)) {
			try await sut.parse(from: url("https://shop.example.com/products/\(value)"))
		}
	}

	@Test(arguments: [("0", 0), ("7", 7), ("1050", 1050)])
	func `int accepts canonical non negative integers`(value: String, expected: Int) async throws {
		let sut = try productParser()

		#expect(try await sut.parse(from: url("https://shop.example.com/products/\(value)")) == [.product(id: expected)])
	}

	@Test
	func `value as Int keeps the lenient conversion`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/products/:id") { match in
			try .product(id: match.value("id", as: Int.self))
		}

		#expect(try await sut.parse(from: url("https://shop.example.com/products/-007")) == [.product(id: -7)])
	}

	@Test
	func `non integer capture throws invalid parameter value`() async throws {
		let sut = try productParser()

		await #expect(throws: DeepLinkError.invalidParameterValue(name: "id", value: "abc")) {
			try await sut.parse(from: url("https://shop.example.com/products/abc"))
		}
	}

	@Test
	func `uuid and lossless string captures convert`() async throws {
		let id = UUID()
		let sut = try PathPatternParser<PatternRoute>("/orders/:id/:flag") { match in
			try .order(id: match.uuid("id"), flag: match.value("flag", as: Bool.self))
		}

		let routes = try await sut.parse(from: url("https://example.com/orders/\(id.uuidString)/true"))

		#expect(routes == [.order(id: id, flag: true)])
	}

	@Test
	func `subscript returns nil for unknown capture names`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/search") { match in
			.search(query: match["missing"] ?? "none")
		}

		#expect(try await sut.parse(from: url("https://example.com/search")) == [.search(query: "none")])
	}

	@Test
	func `string for an undeclared capture throws missing required parameter`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/search") { match in
			try .search(query: match.string("q"))
		}

		await #expect(throws: DeepLinkError.missingRequiredParameter("q")) {
			try await sut.parse(from: url("https://example.com/search"))
		}
	}

	// MARK: - Canonical Path Safety

	@Test(arguments: [
		"https://example.com/products/..",
		"https://example.com/products/%2e%2e",
		"https://example.com/products/%2E%2E/admin",
		"https://example.com/products/.",
	])
	func `dot segments are rejected as traversal`(string: String) async throws {
		let sut = try PathPatternParser<PatternRoute>("/products/*") { _ in .home }

		await #expect(throws: DeepLinkError.securityViolation("Path traversal is not allowed")) {
			try await sut.parse(from: url(string))
		}
	}

	@Test
	func `encoded slash inside a capture is rejected rather than split`() async throws {
		let sut = try productParser()

		await #expect(throws: DeepLinkError.invalidParameterValue(name: "id", value: "1/2")) {
			try await sut.parse(from: url("https://shop.example.com/products/1%2F2"))
		}
	}

	@Test
	func `double encoded traversal is not decoded into a dot segment`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/files/:name") { match in
			try .search(query: match.string("name"))
		}

		await #expect(throws: DeepLinkError.invalidParameterValue(name: "name", value: "%2e%2e")) {
			try await sut.parse(from: url("https://example.com/files/%252e%252e"))
		}
	}

	@Test(arguments: ["%00", "a%0Ab", "caf%C3%A9", "a%20b", "a@b"])
	func `captures outside the default charset are rejected`(segment: String) async throws {
		let sut = try PathPatternParser<PatternRoute>("/files/:name") { match in
			try .search(query: match.string("name"))
		}

		await #expect(throws: DeepLinkError.self) {
			try await sut.parse(from: url("https://example.com/files/\(segment)"))
		}
	}

	@Test
	func `custom charset admits additional characters`() async throws {
		let sut = try PathPatternParser<PatternRoute>(
			"/u/:handle",
			allowedCharacters: PathPatternParser<PatternRoute>.defaultAllowedCharacters.union(CharacterSet(charactersIn: "@")),
		) { match in
			try .posts(handle: match.string("handle"), rest: [])
		}

		#expect(try await sut.parse(from: url("https://example.com/u/@ana")) == [.posts(handle: "@ana", rest: [])])
	}

	@Test
	func `wildcard segments are validated against the charset`() async throws {
		let sut = try PathPatternParser<PatternRoute>("/u/*") { _ in .home }

		await #expect(throws: DeepLinkError.invalidParameterValue(name: "*", value: "a b")) {
			try await sut.parse(from: url("https://example.com/u/ok/a%20b"))
		}
	}

	// MARK: - Template Validation

	@Test(arguments: [
		("/products/:", PathPatternError.invalidCaptureName(":")),
		("/products/:1id", PathPatternError.invalidCaptureName(":1id")),
		("/a/:id/b/:id", PathPatternError.duplicateCaptureName("id")),
		("/files/*/edit", PathPatternError.wildcardNotLast),
		("/a/../b", PathPatternError.invalidLiteral("..")),
		("/a/%2e", PathPatternError.invalidLiteral("%2e")),
		("/search?q=1", PathPatternError.invalidLiteral("search?q=1")),
		("/a*b", PathPatternError.invalidLiteral("a*b")),
	])
	func `invalid templates throw a descriptive error`(template: String, expected: PathPatternError) {
		#expect(throws: expected) {
			try PathPatternParser<PatternRoute>(template) { _ in .home }
		}
	}

	@Test
	func `template errors describe the problem`() {
		#expect(PathPatternError.duplicateCaptureName("id").errorDescription == "Duplicate capture name 'id' in path pattern")
		#expect(PathPatternError.wildcardNotLast.errorDescription == "The '*' wildcard must be the last segment of a path pattern")
	}

	// MARK: - Integration

	@Test
	func `factory parsers compose in default routing`() async throws {
		let routing = try DefaultDeepLinkRouting<PatternRoute>(parsers: [
			.pattern("/products/:id") { match in try .product(id: match.int("id")) },
			.pattern("/search") { _ in .search(query: "") },
		])

		#expect(try await routing.route(from: url("https://example.com/search")) == [.search(query: "")])
		await #expect(throws: DeepLinkError.self) {
			try await routing.route(from: url("https://example.com/unknown"))
		}
	}

	// MARK: - Helpers

	private func productParser(hosts: Set<String> = []) throws -> PathPatternParser<PatternRoute> {
		try PathPatternParser("/products/:id", hosts: hosts) { match in
			try .product(id: match.int("id"))
		}
	}

	private func url(_ string: String) -> URL {
		URL(string: string)!
	}
}

private enum PatternRoute: DeepLinkRoute {
	case home
	case product(id: Int)
	case posts(handle: String, rest: [String])
	case search(query: String)
	case order(id: UUID, flag: Bool)

	var id: String {
		String(describing: self)
	}
}
