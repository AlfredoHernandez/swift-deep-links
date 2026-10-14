//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkMiddlewareFactoryTests {
	private let sampleURL = URL(string: "myapp://profile")!

	// MARK: - Analytics

	@Test
	func `analytics factory forwards URLs to the provider`() async throws {
		let provider = AnalyticsProviderSpy()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider)

		let result = try await middleware.intercept(sampleURL)

		#expect(result == sampleURL)
		#expect(provider.trackedEvents.count == 1)
	}

	@Test
	func `analytics factory honours the strategy it was built with`() async throws {
		let provider = AnalyticsProviderSpy()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider, strategy: .minimal)

		_ = try await middleware.intercept(sampleURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["url"] == nil)
		#expect(event.parameters["scheme"] as? String == "myapp")
	}

	// MARK: - Logging

	@Test
	func `logging factory passes URLs through unchanged`() async throws {
		let middleware: any DeepLinkMiddleware = .logging()

		let result = try await middleware.intercept(sampleURL)

		#expect(result == sampleURL)
	}

	// MARK: - RateLimit

	@Test
	func `rateLimit factory stops returning the URL after the request limit is reached`() async throws {
		// Use an in-memory persistence to avoid cross-run pollution from the
		// shared UserDefaults suite that the default would otherwise hit.
		let middleware: any DeepLinkMiddleware = .rateLimit(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: InMemoryRateLimitPersistence(),
		)

		_ = try await middleware.intercept(sampleURL)
		_ = try await middleware.intercept(sampleURL)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 2, timeWindow: 60.0)) {
			try await middleware.intercept(sampleURL)
		}
	}

	// MARK: - Security

	@Test
	func `security factory throws when the scheme is not allowed`() async throws {
		let middleware: any DeepLinkMiddleware = .security(allowedSchemes: ["myapp"])
		let blockedURL = try #require(URL(string: "https://example.com"))

		await #expect(throws: DeepLinkError.self) {
			try await middleware.intercept(blockedURL)
		}
	}

	@Test
	func `security factory passes through when the URL matches policy`() async throws {
		let middleware: any DeepLinkMiddleware = .security(allowedSchemes: ["myapp"])

		let result = try await middleware.intercept(sampleURL)

		#expect(result == sampleURL)
	}

	// MARK: - Authentication

	@Test
	func `authentication factory halts when the provider reports unauthenticated access to a protected host`() async throws {
		let provider = AuthenticationProviderStub(isAuthenticated: false)
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: ["profile"],
		)

		await #expect(throws: DeepLinkError.self) {
			try await middleware.intercept(sampleURL)
		}
	}

	@Test
	func `authentication factory lets authenticated URLs through`() async throws {
		let provider = AuthenticationProviderStub(isAuthenticated: true)
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: ["profile"],
		)

		let result = try await middleware.intercept(sampleURL)

		#expect(result == sampleURL)
	}

	// MARK: - URLTransformation

	@Test
	func `urlTransformation factory runs the supplied transformer on the URL`() async throws {
		let transformer = URLNormalizationTransformer()
		let middleware: any DeepLinkMiddleware = .urlTransformation(transformer: transformer)
		let messyURL = try #require(URL(string: "myapp://profile/?id=123&name="))

		let result = try await middleware.intercept(messyURL)

		// `URLNormalizationTransformer` strips the trailing slash from the path
		// and drops empty query values, so asserting the exact normalised URL
		// proves the factory actually wired the transformer (an identity
		// transformer would round-trip `messyURL` verbatim).
		#expect(result?.absoluteString == "myapp://profile?id=123")
	}
}
