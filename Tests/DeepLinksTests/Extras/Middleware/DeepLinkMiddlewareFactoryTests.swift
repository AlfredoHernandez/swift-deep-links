//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@Suite("DeepLinkMiddleware Factory Methods Tests")
struct DeepLinkMiddlewareFactoryTests {
	@Test("Analytics factory method creates middleware with correct type")
	func analytics_factoryMethod_createsMiddlewareWithCorrectType() {
		let provider = DefaultAnalyticsProvider()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider)

		#expect(middleware is AnalyticsMiddleware)
	}

	@Test("Analytics factory method with strategy creates middleware")
	func analytics_factoryMethodWithStrategy_createsMiddleware() {
		let provider = DefaultAnalyticsProvider()
		let middleware: any DeepLinkMiddleware = .analytics(provider: provider, strategy: .detailed)

		#expect(middleware is AnalyticsMiddleware)
	}

	@Test("Logging factory method creates middleware with correct type")
	func logging_factoryMethod_createsMiddlewareWithCorrectType() {
		let middleware: any DeepLinkMiddleware = .logging()

		#expect(middleware is LoggingMiddleware)
	}

	@Test("Logging factory method with parameters creates middleware")
	func logging_factoryMethodWithParameters_createsMiddleware() {
		let middleware: any DeepLinkMiddleware = .logging(
			provider: .defaultSystemLogger(),
			logLevel: .debug,
			format: .detailed,
		)

		#expect(middleware is LoggingMiddleware)
	}

	@Test("RateLimit factory method creates middleware with correct type")
	func rateLimit_factoryMethod_createsMiddlewareWithCorrectType() {
		let middleware: any DeepLinkMiddleware = .rateLimit()

		#expect(middleware is RateLimitMiddleware)
	}

	@Test("RateLimit factory method with parameters creates middleware")
	func rateLimit_factoryMethodWithParameters_createsMiddleware() {
		let middleware: any DeepLinkMiddleware = .rateLimit(
			maxRequests: 5,
			timeWindow: 30.0,
			strategy: .fixedWindow,
		)

		#expect(middleware is RateLimitMiddleware)
	}

	@Test("Security factory method creates middleware with correct type")
	func security_factoryMethod_createsMiddlewareWithCorrectType() {
		let middleware: any DeepLinkMiddleware = .security(
			allowedSchemes: ["https", "myapp"],
		)

		#expect(middleware is SecurityMiddleware)
	}

	@Test("Security factory method with all parameters creates middleware")
	func security_factoryMethodWithAllParameters_createsMiddleware() {
		let middleware: any DeepLinkMiddleware = .security(
			allowedSchemes: ["https"],
			allowedHosts: ["secure.myapp.com"],
			blockedPatterns: [],
			strategy: .strict,
		)

		#expect(middleware is SecurityMiddleware)
	}

	@Test("Authentication factory method creates middleware with correct type")
	func authentication_factoryMethod_createsMiddlewareWithCorrectType() {
		let provider = PermissiveAuthenticationProvider()
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: ["secure.myapp.com"],
		)

		#expect(middleware is AuthenticationMiddleware)
	}

	@Test("Authentication factory method with strategy creates middleware")
	func authentication_factoryMethodWithStrategy_createsMiddleware() {
		let provider = PermissiveAuthenticationProvider()
		let middleware: any DeepLinkMiddleware = .authentication(
			provider: provider,
			protectedHosts: [],
			strategy: .strict,
		)

		#expect(middleware is AuthenticationMiddleware)
	}

	@Test("URLTransformation factory method creates middleware with correct type")
	func urlTransformation_factoryMethod_createsMiddlewareWithCorrectType() {
		let transformer = URLNormalizationTransformer()
		let middleware: any DeepLinkMiddleware = .urlTransformation(transformer: transformer)

		#expect(middleware is URLTransformationMiddleware)
	}

	@Test("URLTransformation factory method with strategy creates middleware")
	func urlTransformation_factoryMethodWithStrategy_createsMiddleware() {
		let transformer = URLNormalizationTransformer()
		let middleware: any DeepLinkMiddleware = .urlTransformation(
			transformer: transformer,
			strategy: .safe,
		)

		#expect(middleware is URLTransformationMiddleware)
	}

	@Test("Factory methods can be used in arrays")
	func factoryMethods_canBeUsedInArrays() {
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
