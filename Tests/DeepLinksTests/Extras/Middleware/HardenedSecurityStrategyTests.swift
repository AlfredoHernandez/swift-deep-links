//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct HardenedSecurityStrategyTests {
	@Test
	func `hardened accepts an allowed URL and returns its canonical form`() async throws {
		let sut = makeSUT(allowedSchemes: ["https"], allowedHosts: ["example.com"])
		let url = try #require(URL(string: "HTTPS://Example.com/Products?ID=7"))

		let result = try await sut.intercept(url: url)

		#expect(result?.absoluteString == "https://example.com/Products?ID=7")
	}

	@Test
	func `hardened compares allow-lists case-insensitively`() async throws {
		let sut = makeSUT(allowedSchemes: ["MyApp"], allowedHosts: ["Home"])
		let url = try #require(URL(string: "myapp://home"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `hardened rejects a scheme that is not allowed`() async throws {
		let sut = makeSUT(allowedSchemes: ["myapp"], allowedHosts: ["home"])
		let url = try #require(URL(string: "otherapp://home"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized scheme")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects a URL without a host`() async throws {
		let sut = makeSUT(allowedSchemes: ["myapp"], allowedHosts: ["home"])
		let url = try #require(URL(string: "myapp:home"))

		await #expect(throws: DeepLinkError.securityViolation("Missing host")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects a host that is not allowed`() async throws {
		let sut = makeSUT(allowedSchemes: ["https"], allowedHosts: ["example.com"])
		let url = try #require(URL(string: "https://evil.com/path"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects every host when the host allow-list is empty`() async throws {
		let sut = makeSUT(allowedSchemes: ["https"], allowedHosts: [])
		let url = try #require(URL(string: "https://example.com/path"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects userinfo that disguises the real host`() async throws {
		let sut = makeSUT(allowedSchemes: ["https"], allowedHosts: ["example.com", "evil.com"])
		let url = try #require(URL(string: "https://example.com@evil.com/path"))

		await #expect(throws: DeepLinkError.securityViolation("Userinfo is not allowed")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects encoded control characters`() async throws {
		let sut = makeSUT(allowedSchemes: ["myapp"], allowedHosts: ["home"])
		let url = try #require(URL(string: "myapp://home/path?q=%00"))

		await #expect(throws: DeepLinkError.securityViolation("Control characters are not allowed")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened rejects encoded path traversal`() async throws {
		let sut = makeSUT(allowedSchemes: ["myapp"], allowedHosts: ["home"])
		let url = try #require(URL(string: "myapp://home/files/%2e%2e/secrets"))

		await #expect(throws: DeepLinkError.securityViolation("Path traversal is not allowed")) {
			try await sut.intercept(url: url)
		}
	}

	@Test(arguments: [
		"myapp://home/open?target=%6A%61vascript:alert(1)",
		"myapp://home/open?target=JavaScript:alert(1)",
		"myapp://home/open?target=%256A%2561vascript:alert(1)",
		"myapp://home/open?target=%256A%61vascript:alert(1)%25zz",
	])
	func `hardened matches blocked patterns case-insensitively against decoded forms`(rawURL: String) async throws {
		let sut = try makeSUT(
			allowedSchemes: ["myapp"],
			allowedHosts: ["home"],
			blockedPatterns: [NSRegularExpression(pattern: "javascript:")],
		)
		let url = try #require(URL(string: rawURL))

		await #expect(throws: DeepLinkError.blockedURL(url)) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened lets a URL through when no blocked pattern matches any form`() async throws {
		let sut = try makeSUT(
			allowedSchemes: ["myapp"],
			allowedHosts: ["home"],
			blockedPatterns: [NSRegularExpression(pattern: "javascript:")],
		)
		let url = try #require(URL(string: "myapp://home/open?target=%2Fprofile"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `case-insensitive pattern compilation fails closed when the pattern cannot be recompiled`() {
		#expect(throws: DeepLinkError.securityViolation("Invalid blocked pattern")) {
			try caseInsensitiveRegex(pattern: "(", options: [])
		}
	}

	@Test
	func `case-insensitive pattern compilation preserves the original options`() throws {
		let regex = try caseInsensitiveRegex(pattern: "a.b", options: [.dotMatchesLineSeparators])

		#expect(regex.options.contains(.caseInsensitive))
		#expect(regex.options.contains(.dotMatchesLineSeparators))
	}

	@Test
	func `security factory accepts the hardened strategy`() async throws {
		let sut: SecurityMiddleware = .security(allowedSchemes: ["myapp"], allowedHosts: ["home"], strategy: .hardened)
		let url = try #require(URL(string: "myapp:home"))

		await #expect(throws: DeepLinkError.securityViolation("Missing host")) {
			try await sut.intercept(url: url)
		}
	}

	private func makeSUT(
		allowedSchemes: Set<String>,
		allowedHosts: Set<String>,
		blockedPatterns: [NSRegularExpression] = [],
	) -> SecurityMiddleware {
		SecurityMiddleware(
			allowedSchemes: allowedSchemes,
			allowedHosts: allowedHosts,
			blockedPatterns: blockedPatterns,
			strategy: .hardened,
		)
	}
}

/// Pins the pre-existing strategies so the hardened work cannot change them.
struct ExistingSecurityStrategiesCompatibilityTests {
	@Test
	func `standard still matches blocked patterns against the raw encoded string only`() async throws {
		let sut = try SecurityMiddleware(
			allowedSchemes: ["myapp"],
			blockedPatterns: [NSRegularExpression(pattern: "javascript:")],
			strategy: .standard,
		)
		let url = try #require(URL(string: "myapp://home/open?target=%6A%61vascript:alert(1)"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `standard still compares schemes case-sensitively`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], strategy: .standard)
		let url = try #require(URL(string: "MYAPP://home"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized scheme")) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `standard still accepts any host and userinfo when the host allow-list is empty`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["https"], strategy: .standard)
		let url = try #require(URL(string: "https://example.com@evil.com/path"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `strict still returns the URL unchanged without canonicalizing it`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["https"], allowedHosts: ["Example.com"], strategy: .strict)
		let url = try #require(URL(string: "https://Example.com/path"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test(arguments: ["myapp:///account/x", "myapp://?a=1", "MYAPP:///x"])
	func `hardened rejects an empty authority host`(rawURL: String) async throws {
		let url = try #require(URL(string: rawURL))
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"])

		await #expect(throws: DeepLinkError.securityViolation("Missing host")) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test
	func `hardened accepts a protected host spelled with a trailing dot or encoding as the canonical host`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["account"])

		#expect(try await sut.intercept(url: #require(URL(string: "myapp://account./x"))) == URL(string: "myapp://account/x"))
		#expect(try await sut.intercept(url: #require(URL(string: "myapp://account%2e/x"))) == URL(string: "myapp://account/x"))
	}
}
