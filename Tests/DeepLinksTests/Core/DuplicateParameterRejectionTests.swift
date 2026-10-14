//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DuplicateParameterRejectionTests {
	private static let duplicateURL = URL(string: "myapp://product?id=1&id=2")!
	private static let duplicateViolation = DeepLinkError.securityViolation("Duplicate query parameter")

	@Test
	func `limits allow duplicate parameters by default`() throws {
		#expect(!DeepLinkInputLimits().rejectDuplicateParameters)
		try DeepLinkInputLimits().validate(Self.duplicateURL)
	}

	@Test(arguments: ["myapp://product?id=1&id=2", "myapp://product?flag&flag", "myapp://product?id=1&%69d=2"])
	func `limits reject a repeated key when configured`(rawURL: String) throws {
		let url = try #require(URL(string: rawURL))
		let sut = DeepLinkInputLimits(rejectDuplicateParameters: true)

		#expect(throws: Self.duplicateViolation) {
			try sut.validate(url)
		}
	}

	@Test
	func `limits accept distinct keys when rejecting duplicates`() throws {
		let url = try #require(URL(string: "myapp://product?id=1&ID=2&&flag"))

		try DeepLinkInputLimits(rejectDuplicateParameters: true).validate(url)
	}

	@Test
	func `security middleware rejects duplicates before the strategy runs`() async throws {
		let sut = SecurityMiddleware(
			allowedSchemes: [],
			strategy: .hardened,
			limits: DeepLinkInputLimits(rejectDuplicateParameters: true),
		)

		await #expect(throws: Self.duplicateViolation) {
			try await sut.intercept(Self.duplicateURL)
		}
	}

	@Test
	func `canonicalizer rejects duplicates when its limits say so`() {
		let sut = URLCanonicalizer(limits: DeepLinkInputLimits(rejectDuplicateParameters: true))

		#expect(throws: Self.duplicateViolation) {
			try sut.canonicalize(Self.duplicateURL)
		}
	}

	@Test
	func `routing accepts duplicates by default`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let sut = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])

		#expect(try await sut.route(from: Self.duplicateURL) == [.route1])
	}

	@Test
	func `routing rejects duplicates before any parser runs when configured`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let sut = DefaultDeepLinkRouting<TestRoute>(parsers: [parser], rejectDuplicateParameters: true)

		await #expect(throws: Self.duplicateViolation) {
			try await sut.route(from: Self.duplicateURL)
		}
		#expect(parser.parseCalledWith == nil)
	}

	@Test
	func `routing still reports oversized URLs as invalid when rejecting duplicates`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let sut = DefaultDeepLinkRouting<TestRoute>(parsers: [parser], rejectDuplicateParameters: true)
		let value = String(repeating: "v", count: DeepLinkURL.defaultMaxLength)
		let url = try #require(URL(string: "myapp://product?id=\(value)&id=2"))

		await #expect(throws: DeepLinkError.invalidURL(url)) {
			try await sut.route(from: url)
		}
	}
}
