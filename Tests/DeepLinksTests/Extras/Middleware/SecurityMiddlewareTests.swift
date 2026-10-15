//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct SecurityMiddlewareTests {
	@Test
	func `SecurityMiddleware allows requests with allowed schemes`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp", "myapp"],
			allowedHosts: [],
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
	}

	@Test
	func `SecurityMiddleware blocks requests with disallowed schemes`() async throws {
		let testURL = try #require(URL(string: "http://test"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [],
			blockedPatterns: [],
		)

		do {
			_ = try await middleware.intercept(url: testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized scheme"))
		}
	}

	@Test
	func `SecurityMiddleware allows requests with allowed hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://allowed"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: ["allowed", "permitted"],
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
	}

	@Test
	func `SecurityMiddleware blocks requests with disallowed hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://disallowed"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: ["allowed"],
			blockedPatterns: [],
		)

		do {
			_ = try await middleware.intercept(url: testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized host"))
		}
	}

	@Test
	func `SecurityMiddleware blocks requests matching blocked patterns`() async throws {
		let testURL = try #require(URL(string: "testapp://malicious"))
		let blockedPattern = try NSRegularExpression(pattern: "malicious")
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [],
			blockedPatterns: [blockedPattern],
		)

		do {
			_ = try await middleware.intercept(url: testURL)
			#expect(Bool(false), "Expected blocked URL error")
		} catch let error as DeepLinkError {
			#expect(error == .blockedURL(testURL))
		}
	}

	@Test
	func `SecurityMiddleware allows requests when no hosts are specified`() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [], // Empty means all hosts allowed
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
	}

	@Test
	func `SecurityMiddleware applies the recommended input limits by default`() async throws {
		let oversized = try #require(URL(string: "testapp://host?q=" + String(repeating: "a", count: DeepLinkURL.defaultMaxLength)))

		await #expect(throws: DeepLinkError.securityViolation("URL exceeds maximum length")) {
			_ = try await SecurityMiddleware(allowedSchemes: ["testapp"]).intercept(url: oversized)
		}
		await #expect(throws: DeepLinkError.securityViolation("URL exceeds maximum length")) {
			_ = try await SecurityMiddleware.security(allowedSchemes: ["testapp"]).intercept(url: oversized)
		}
	}

	@Test(arguments: [SecurityStrategy.hardened, .standard, .strict, .hostOnly, .whitelist])
	func `SecurityMiddleware does not echo an unauthorized host in the violation`(strategy: SecurityStrategy) async throws {
		let host = String(repeating: "h", count: 5000)
		let url = try #require(URL(string: "testapp://\(host)"))
		let middleware = SecurityMiddleware(allowedSchemes: ["testapp"], allowedHosts: ["allowed"], strategy: strategy, limits: .unlimited)

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			_ = try await middleware.intercept(url: url)
		}
	}

	@Test(arguments: [SecurityStrategy.hardened, .standard, .strict, .permissive, .schemeOnly, .whitelist])
	func `SecurityMiddleware does not echo an unauthorized scheme in the violation`(strategy: SecurityStrategy) async throws {
		let url = try #require(URL(string: "evil-scheme://allowed"))
		let middleware = SecurityMiddleware(allowedSchemes: ["testapp"], allowedHosts: ["allowed"], strategy: strategy)

		await #expect(throws: DeepLinkError.securityViolation("Unauthorized scheme")) {
			_ = try await middleware.intercept(url: url)
		}
	}
}
