//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import os
import Testing

struct SecurityMiddlewareInputLimitsTests {
	@Test
	func `limits reject an oversized URL before the strategy runs`() async throws {
		let strategy = SecurityStrategySpy()
		let sut = SecurityMiddleware(
			allowedSchemes: ["myapp"],
			strategy: strategy.strategy,
			limits: DeepLinkInputLimits(maxURLLength: 16),
		)
		let url = try #require(URL(string: "myapp://home/a-path-longer-than-sixteen"))

		await #expect(throws: DeepLinkError.securityViolation("URL exceeds maximum length")) {
			try await sut.intercept(url: url)
		}
		#expect(strategy.validatedURLs.isEmpty)
	}

	@Test
	func `limits reject too many query parameters before the strategy runs`() async throws {
		let strategy = SecurityStrategySpy()
		let sut = SecurityMiddleware(
			allowedSchemes: ["myapp"],
			strategy: strategy.strategy,
			limits: DeepLinkInputLimits(maxQueryParameterCount: 1),
		)
		let url = try #require(URL(string: "myapp://home?a=1&b=2"))

		await #expect(throws: DeepLinkError.securityViolation("Too many query parameters")) {
			try await sut.intercept(url: url)
		}
		#expect(strategy.validatedURLs.isEmpty)
	}

	@Test
	func `a URL within limits reaches the strategy`() async throws {
		let strategy = SecurityStrategySpy()
		let sut = SecurityMiddleware(
			allowedSchemes: ["myapp"],
			strategy: strategy.strategy,
			limits: .recommended,
		)
		let url = try #require(URL(string: "myapp://home?a=1"))

		let result = try await sut.intercept(url: url)

		#expect(result == url)
		#expect(strategy.validatedURLs == [url])
	}

	@Test
	func `unlimited limits accept an oversized link`() async throws {
		let sut = SecurityMiddleware(allowedSchemes: ["myapp"], limits: .unlimited)
		let value = String(repeating: "v", count: DeepLinkURL.defaultMaxLength)
		let url = try #require(URL(string: "myapp://home?a=\(value)"))

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `security factory forwards limits`() async throws {
		let sut: SecurityMiddleware = .security(allowedSchemes: ["myapp"], limits: DeepLinkInputLimits(maxParameterValueLength: 2))
		let url = try #require(URL(string: "myapp://home?token=abc"))

		await #expect(throws: DeepLinkError.securityViolation("Query parameter value exceeds maximum length")) {
			try await sut.intercept(url: url)
		}
	}
}

private final class SecurityStrategySpy: Sendable {
	private let state = OSAllocatedUnfairLock<[URL]>(initialState: [])

	var validatedURLs: [URL] {
		state.withLock { $0 }
	}

	var strategy: SecurityStrategy {
		SecurityStrategy { [state] url, _ in
			state.withLock { $0.append(url) }
			return url
		}
	}
}
