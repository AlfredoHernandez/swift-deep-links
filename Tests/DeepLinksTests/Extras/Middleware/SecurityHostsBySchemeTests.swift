//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct SecurityHostsBySchemeTests {
	private let sut = SecurityMiddleware(
		allowedSchemes: ["https", "myapp"],
		allowedHostsByScheme: ["https": ["example.com"], "myapp": ["home"]],
	)

	@Test(arguments: ["https://example.com/a", "HTTPS://EXAMPLE.com/a", "myapp://home/x", "myapp://Home"])
	func `accepts a host listed for its own scheme`(link: String) async throws {
		let url = try #require(URL(string: link))

		#expect(try await sut.intercept(url: url) != nil)
	}

	@Test(arguments: ["https://home/a", "myapp://example.com/x", "https://evil.com"])
	func `rejects a host listed only for another scheme`(link: String) async throws {
		let url = try #require(URL(string: link))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test
	func `a scheme with an entry requires a host`() async throws {
		let url = try #require(URL(string: "myapp:home"))

		await #expect(throws: DeepLinkError.securityViolation("Missing host")) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test
	func `scheme keys and hosts compare case-insensitively`() async throws {
		let middleware = SecurityMiddleware(allowedSchemes: ["https"], allowedHostsByScheme: ["HTTPS": ["Example.COM"]])
		let url = try #require(URL(string: "https://example.com/a"))

		#expect(try await middleware.intercept(url: url) == url)
	}

	@Test
	func `a scheme entry takes precedence over allowedHosts, which still covers other schemes`() async throws {
		let middleware = SecurityMiddleware(
			allowedSchemes: ["https", "myapp"],
			allowedHosts: ["home"],
			allowedHostsByScheme: ["https": ["example.com"]],
		)

		#expect(try await middleware.intercept(url: #require(URL(string: "myapp://home"))) != nil)
		#expect(try await middleware.intercept(url: #require(URL(string: "https://example.com"))) != nil)
		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await middleware.intercept(url: #require(URL(string: "https://home")))
		}
		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await middleware.intercept(url: #require(URL(string: "myapp://example.com")))
		}
	}

	@Test
	func `an empty entry rejects every link of its scheme`() async throws {
		let middleware: SecurityMiddleware = .security(allowedSchemes: ["myapp"], allowedHostsByScheme: ["myapp": []])

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await middleware.intercept(url: #require(URL(string: "myapp://home")))
		}
	}
}
