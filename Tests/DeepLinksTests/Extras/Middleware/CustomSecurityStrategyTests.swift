//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import Foundation
import os
import Testing

/// Uses only the public API, so it fails to compile if custom strategies
/// lose their public entry points.
struct CustomSecurityStrategyTests {
	@Test
	func `a custom strategy receives the middleware's normalized policy`() async throws {
		let seen = OSAllocatedUnfairLock<SecurityPolicy?>(initialState: nil)
		let strategy = SecurityStrategy { url, policy in
			seen.withLock { $0 = policy }
			return url
		}
		let middleware = try SecurityMiddleware(
			allowedSchemes: ["MyApp"],
			allowedHosts: ["Home."],
			blockedPatterns: [NSRegularExpression(pattern: "admin")],
			strategy: strategy,
			limits: .unlimited,
		)

		_ = try await middleware.intercept(DeepLinkRequest(url: #require(URL(string: "myapp://home/x"))))

		let policy = try #require(seen.withLock { $0 })
		#expect(policy.allowedSchemes == ["myapp"])
		#expect(policy.allowedHosts == ["home"])
		#expect(try policy.blockedPatterns().map(\.pattern) == ["admin"])
		#expect(try policy.blockedPatterns().allSatisfy { $0.options.contains(.caseInsensitive) })
	}

	@Test
	func `a custom strategy can rewrite, stop or reject the link`() async throws {
		let strategy = SecurityStrategy { url, _ in
			switch url.host() {
			case "old": URL(string: "myapp://new")
			case "drop": nil
			default: throw DeepLinkError.securityViolation("Not on the list")
			}
		}
		let middleware = SecurityMiddleware(allowedSchemes: ["myapp"], strategy: strategy)

		let rewritten = try await middleware.intercept(DeepLinkRequest(url: #require(URL(string: "myapp://old"))))
		let dropped = try await middleware.intercept(DeepLinkRequest(url: #require(URL(string: "myapp://drop"))))
		let other = try #require(URL(string: "myapp://other"))

		#expect(rewritten?.url == URL(string: "myapp://new"))
		#expect(dropped == nil)
		await #expect(throws: DeepLinkError.securityViolation("Not on the list")) {
			try await middleware.intercept(DeepLinkRequest(url: other))
		}
	}

	@Test
	func `a custom strategy can decorate a built-in one`() async throws {
		let noAdmin = SecurityStrategy { url, policy in
			guard !url.path().hasPrefix("/admin") else {
				throw DeepLinkError.securityViolation("Admin links are not allowed")
			}
			return try await SecurityStrategy.hardened.validate(url: url, policy: policy)
		}
		let middleware = SecurityMiddleware(allowedSchemes: ["https"], allowedHosts: ["example.com"], strategy: noAdmin)

		let canonical = try await middleware.intercept(DeepLinkRequest(url: #require(URL(string: "HTTPS://Example.com/home"))))
		let admin = try #require(URL(string: "https://example.com/admin"))
		let foreign = try #require(URL(string: "https://evil.com/home"))

		#expect(canonical?.url == URL(string: "https://example.com/home"))
		await #expect(throws: DeepLinkError.securityViolation("Admin links are not allowed")) {
			try await middleware.intercept(DeepLinkRequest(url: admin))
		}
		await #expect(throws: DeepLinkError.self) {
			try await middleware.intercept(DeepLinkRequest(url: foreign))
		}
	}

	@Test
	func `a policy built directly lets a strategy be tested without middleware`() async throws {
		let policy = SecurityPolicy(allowedSchemes: ["MyApp"], allowedHostsByScheme: ["MYAPP": ["Home."]])
		let url = try #require(URL(string: "myapp://evil"))

		#expect(policy.allowedHosts(forScheme: "myapp") == ["home"])
		#expect(policy.allowedHosts(forScheme: "https") == nil)
		await #expect(throws: DeepLinkError.securityViolation("Unauthorized host")) {
			try await SecurityStrategy.hardened.validate(url: url, policy: policy)
		}
	}
}
