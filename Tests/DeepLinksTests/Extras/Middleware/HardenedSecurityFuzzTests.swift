//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct HardenedSecurityFuzzTests {
	private static let strictLimits = DeepLinkInputLimits(
		maxURLLength: DeepLinkURL.defaultMaxLength,
		maxQueryParameterCount: 50,
		maxParameterValueLength: 1024,
		rejectDuplicateParameters: true,
	)

	private let sut = SecurityMiddleware(
		allowedSchemes: ["https"],
		allowedHosts: ["example.com"],
		strategy: .hardened,
		limits: strictLimits,
	)

	@Test(arguments: URLFuzzCorpus.hostile(scheme: "https", host: "example.com"))
	func `hardened security rejects every hostile URL`(fuzzCase: URLFuzzCase) async {
		await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(url: fuzzCase.url)
		}
	}

	@Test(arguments: URLFuzzCorpus.hostile(scheme: "myapp", host: "product"))
	func `hardened security rejects every hostile custom scheme URL`(fuzzCase: URLFuzzCase) async {
		let customScheme = SecurityMiddleware(
			allowedSchemes: ["myapp"],
			allowedHosts: ["product"],
			strategy: .hardened,
			limits: Self.strictLimits,
		)

		await #expect(throws: DeepLinkError.self) {
			try await customScheme.intercept(url: fuzzCase.url)
		}
	}

	@Test
	func `the same configuration admits a benign URL`() async throws {
		let benign = try #require(URL(string: "https://example.com/products/42?ref=home"))

		#expect(try await sut.intercept(url: benign) == benign)
	}
}
