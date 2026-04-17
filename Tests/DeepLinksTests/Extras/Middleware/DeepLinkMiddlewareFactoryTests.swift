//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkMiddlewareFactoryTests {
	@Test
	func `Analytics factory method creates middleware with correct type`() {
		let provider = DefaultAnalyticsProvider()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider)

		#expect(middleware is AnalyticsMiddleware)
	}

	@Test
	func `Analytics factory method with strategy creates middleware`() {
		let provider = DefaultAnalyticsProvider()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider, strategy: .detailed)

		#expect(middleware is AnalyticsMiddleware)
	}

	@Test
	func `Logging factory method creates middleware with correct type`() {
		let middleware: any DeepLinkMiddleware = .logging()

		#expect(middleware is LoggingMiddleware)
	}

	@Test
	func `Logging factory method with parameters creates middleware`() {
		let middleware: any DeepLinkMiddleware = .logging(
			provider: .defaultSystemLogger(),
			logLevel: .debug,
			format: .detailed,
		)

		#expect(middleware is LoggingMiddleware)
	}

	@Test
	func `RateLimit factory method creates middleware with correct type`() {
		let middleware: any DeepLinkMiddleware = .rateLimit()

		#expect(middleware is RateLimitMiddleware)
	}

	@Test
	func `RateLimit factory method with parameters creates middleware`() {
		let middleware: any DeepLinkMiddleware = .rateLimit(
			maxRequests: 5,
			timeWindow: 30.0,
			strategy: .fixedWindow,
		)

		#expect(middleware is RateLimitMiddleware)
	}

	@Test
	func `Security factory method creates middleware with correct type`() {
		let middleware: any DeepLinkMiddleware = .security(
			allowedSchemes: ["https", "myapp"],
		)

		#expect(middleware is SecurityMiddleware)
	}

	@Test
	func `Security factory method with all parameters creates middleware`() {
		let middleware: any DeepLinkMiddleware = .security(
			allowedSchemes: ["https"],
			allowedHosts: ["secure.myapp.com"],
			blockedPatterns: [],
			strategy: .strict,
		)

		#expect(middleware is SecurityMiddleware)
	}

	@Test
	func `Authentication factory method creates middleware with correct type`() {
		let provider = PermissiveAuthenticationProvider()
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: ["secure.myapp.com"],
		)

		#expect(middleware is AuthenticationMiddleware)
	}

	@Test
	func `Authentication factory method with strategy creates middleware`() {
		let provider = PermissiveAuthenticationProvider()
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: [],
			strategy: .strict,
		)

		#expect(middleware is AuthenticationMiddleware)
	}

	@Test
	func `URLTransformation factory method creates middleware with correct type`() {
		let transformer = URLNormalizationTransformer()
		let middleware: any DeepLinkMiddleware = .urlTransformation(transformer: transformer)

		#expect(middleware is URLTransformationMiddleware)
	}

	@Test
	func `URLTransformation factory method with strategy creates middleware`() {
		let transformer = URLNormalizationTransformer()
		let middleware: any DeepLinkMiddleware = .urlTransformation(
			transformer: transformer,
			strategy: .safe,
		)

		#expect(middleware is URLTransformationMiddleware)
	}

	@Test
	func `Factory methods can be used in arrays`() {
		let provider = DefaultAnalyticsProvider()
		let authProvider = PermissiveAuthenticationProvider()
		let transformer = URLNormalizationTransformer()

		let middleware: [any DeepLinkMiddleware] = [
			.analytics(provider: provider),
			.logging(),
			.rateLimit(maxRequests: 10, timeWindow: 60),
			.security(allowedSchemes: ["https", "myapp"]),
			.authentication(provider: authProvider, protectedHosts: []),
			.urlTransformation(transformer: transformer),
		]

		#expect(middleware.count == 6)
		#expect(middleware[0] is AnalyticsMiddleware)
		#expect(middleware[1] is LoggingMiddleware)
		#expect(middleware[2] is RateLimitMiddleware)
		#expect(middleware[3] is SecurityMiddleware)
		#expect(middleware[4] is AuthenticationMiddleware)
		#expect(middleware[5] is URLTransformationMiddleware)
	}
}
