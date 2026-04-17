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

		let result = try await middleware.intercept(testURL)

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
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized scheme: http"))
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

		let result = try await middleware.intercept(testURL)

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
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected security violation error")
		} catch let error as DeepLinkError {
			#expect(error == .securityViolation("Unauthorized host: disallowed"))
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
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected blocked URL error")
		} catch let error as DeepLinkError {
			#expect(error == .blockedURL(testURL.absoluteString))
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

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}
}
