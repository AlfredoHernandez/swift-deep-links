//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("SecurityMiddleware Tests")
struct SecurityMiddlewareTests {
	@Test("SecurityMiddleware allows requests with allowed schemes")
	func securityMiddleware_allowsRequestsWithAllowedSchemes() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp", "myapp"],
			allowedHosts: [],
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test("SecurityMiddleware blocks requests with disallowed schemes")
	func securityMiddleware_blocksRequestsWithDisallowedSchemes() async throws {
		let testURL = try #require(URL(string: "http://test"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [],
			blockedPatterns: [],
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized scheme: http"))
		}
	}

	@Test("SecurityMiddleware allows requests with allowed hosts")
	func securityMiddleware_allowsRequestsWithAllowedHosts() async throws {
		let testURL = try #require(URL(string: "testapp://allowed"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: ["allowed", "permitted"],
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test("SecurityMiddleware blocks requests with disallowed hosts")
	func securityMiddleware_blocksRequestsWithDisallowedHosts() async throws {
		let testURL = try #require(URL(string: "testapp://disallowed"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: ["allowed"],
			blockedPatterns: [],
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized host: disallowed"))
		}
	}

	@Test("SecurityMiddleware blocks requests matching blocked patterns")
	func securityMiddleware_blocksRequestsMatchingBlockedPatterns() async throws {
		let testURL = try #require(URL(string: "testapp://malicious"))
		let blockedPattern = try NSRegularExpression(pattern: "malicious")
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [],
			blockedPatterns: [blockedPattern],
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected blocked URL error")
		} catch let error as DeepLinkError {
			#expect(error == .blockedURL(testURL.absoluteString))
		}
	}

	@Test("SecurityMiddleware allows requests when no hosts are specified")
	func securityMiddleware_allowsRequestsWhenNoHostsAreSpecified() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
			allowedHosts: [], // Empty means all hosts allowed
			blockedPatterns: [],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}
}
