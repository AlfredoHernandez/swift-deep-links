//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct URLRedactorPathTests {
	@Test
	func `paths are kept by default`() throws {
		let url = try #require(URL(string: "https://example.com/reset/3f9a8c7e2b1d4f6a9e0c"))

		#expect(URLRedactor().redact(url) == url)
	}

	@Test(arguments: [
		("https://example.com/reset/3f9a8c7e2b1d4f6a9e0c", "https://example.com/reset/REDACTED"),
		("https://example.com/i/550e8400-e29b-41d4-a716-446655440000/accept", "https://example.com/i/REDACTED/accept"),
		("myapp://invite/AbCdEf0123456789xyz;v=1?id=2", "myapp://invite/REDACTED;v=1?id=2"),
	])
	func `token-like segments are redacted`(link: String, expected: String) throws {
		let sut = URLRedactor(pathRedaction: .tokenLikeSegments())

		#expect(try sut.redact(#require(URL(string: link))).absoluteString == expected)
	}

	@Test(arguments: [
		"https://example.com/products/1234567890123456789",
		"https://example.com/articles/a-very-long-readable-article-slug",
		"https://example.com/a1/b2",
	])
	func `readable and numeric segments are not token-like`(link: String) throws {
		let url = try #require(URL(string: link))

		#expect(URLRedactor(pathRedaction: .tokenLikeSegments()).redact(url) == url)
	}

	@Test(arguments: [
		("https://example.com/invite/abc/accept", "https://example.com/invite/REDACTED/accept"),
		("https://example.com/INVITE/abc/accept", "https://example.com/INVITE/REDACTED/accept"),
		("myapp://invite/abc/accept", "myapp://invite/REDACTED/accept"),
		("https://example.com/reset/s3cret", "https://example.com/reset/REDACTED"),
		("https://example.com/invite/abc", "https://example.com/invite/abc"),
		("https://example.com/other/abc/accept", "https://example.com/other/abc/accept"),
	])
	func `template placeholders are redacted on matching paths`(link: String, expected: String) throws {
		let sut = URLRedactor(pathRedaction: .templates(["/invite/:code/accept", "reset/:token"]))

		#expect(try sut.redact(#require(URL(string: link))).absoluteString == expected)
	}

	@Test
	func `strategies combine`() throws {
		let sut = URLRedactor(pathRedaction: .anyOf(.templates(["/u/:handle"]), .segments { $0 == "secret" }))

		#expect(try sut.redact(#require(URL(string: "https://e.com/u/ana"))).absoluteString == "https://e.com/u/REDACTED")
		#expect(try sut.redact(#require(URL(string: "https://e.com/x/secret"))).absoluteString == "https://e.com/x/REDACTED")
	}

	@Test
	func `path redaction applies wherever the redactor is used`() throws {
		let redactor = URLRedactor(pathRedaction: .templates(["/reset/:token"]))
		let url = try #require(URL(string: "https://example.com/reset/s3cret"))

		#expect(DeepLinkLogPrivacy.redacted(using: redactor).describe(url) == "https://example.com/reset/REDACTED")
		#expect(DeepLinkError.routeNotFound(url).redactedDescription(using: redactor) == "No route found for URL: https://example.com/reset/REDACTED")
	}

	@Test
	func `confirmation prompts show the path-redacted URL`() async throws {
		let provider = CollectingConfirmation(approves: true)
		let sut = ConfirmationMiddleware(provider: provider, redactor: URLRedactor(pathRedaction: .templates(["/pay/:id"])), timeout: nil)

		_ = try await sut.intercept(DeepLinkRequest(url: #require(URL(string: "myapp://pay/42"))))

		#expect(provider.requests.map(\.url.absoluteString) == ["myapp://pay/REDACTED"])
	}
}
