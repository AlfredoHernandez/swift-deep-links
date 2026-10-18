//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct LegacySecurityStrategyMatchingTests {
	private static let hostCheckingStrategies: [SecurityStrategy] = [.standard, .strict, .hostOnly, .whitelist]
	private static let schemeCheckingStrategies: [SecurityStrategy] = [.standard, .strict, .permissive, .schemeOnly, .whitelist]
	private static let patternCheckingStrategies: [SecurityStrategy] = [.standard, .strict, .permissive, .patternOnly]

	@Test(arguments: schemeCheckingStrategies)
	func `schemes compare case-insensitively`(strategy: SecurityStrategy) async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["MyApp"], allowedHosts: ["home"], strategy: strategy)
		let url = try #require(URL(string: "myapp://home"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test(arguments: hostCheckingStrategies)
	func `hosts compare case-insensitively, decoded and without a trailing dot`(strategy: SecurityStrategy) async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["Home"], strategy: strategy)

		for link in ["myapp://HOME", "myapp://home.", "myapp://%68ome"] {
			let url = try #require(URL(string: link))
			#expect(try await sut.intercept(url: url) == url)
		}
	}

	@Test(arguments: hostCheckingStrategies)
	func `an unlisted host is still rejected`(strategy: SecurityStrategy) async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["home"], strategy: strategy)
		let url = try #require(URL(string: "myapp://home.evil"))

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test(arguments: patternCheckingStrategies)
	func `blocked patterns match case-insensitively against decoded forms`(strategy: SecurityStrategy) async throws {
		let pattern = try NSRegularExpression(pattern: "javascript:")
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: ["home"], blockedPatterns: [pattern], strategy: strategy)
		let url = try #require(URL(string: "myapp://home?next=%6A%61VASCRIPT:alert(1)"))

		await #expect(throws: DeepLinkError.blockedURL(url)) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test
	func `legacy strategies keep their allow-list semantics`() async throws {
		let anyHost = try #require(URL(string: "https://any.example"))
		let hostless = try #require(URL(string: "myapp:path"))

		#expect(try await SecurityMiddleware(allowedSchemes: ["https"], strategy: .standard).intercept(url: anyHost) == anyHost)
		#expect(try await SecurityMiddleware(allowedSchemes: ["https"], allowedHosts: ["x"], strategy: .permissive).intercept(url: anyHost) == anyHost)
		#expect(try await SecurityMiddleware(allowedSchemes: [], strategy: .hostOnly).intercept(url: anyHost) == anyHost)
		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await SecurityMiddleware(allowedSchemes: ["myapp"], allowedHosts: [], strategy: .strict).intercept(url: hostless)
		}
	}
}
