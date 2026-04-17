//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkMiddlewareCoordinatorTests {
	// MARK: - Middleware Coordinator Tests

	@Test
	func `DeepLinkMiddlewareCoordinator processes URL through middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add a simple middleware that returns the URL
		await coordinator.add(MiddlewareSpy())

		let result = try await coordinator.process(testURL)

		#expect(result == testURL)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator stops processing when middleware returns nil`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add middleware that returns nil
		await coordinator.add(MiddlewareStub(result: nil))

		let result = try await coordinator.process(testURL)

		#expect(result == nil)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator processes middleware in order`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add middleware that tracks order
		let firstMiddleware = OrderTrackingSpy(id: "first")
		let secondMiddleware = OrderTrackingSpy(id: "second")

		await coordinator.add(firstMiddleware)
		await coordinator.add(secondMiddleware)

		_ = try await coordinator.process(testURL)

		#expect(firstMiddleware.wasCalled)
		#expect(secondMiddleware.wasCalled)

		// Verify order by checking that first middleware was called before second
		#expect(try #require(firstMiddleware.callTimes.first) < secondMiddleware.callTimes.first!)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator transforms URL through middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://transformed"))

		// Add middleware that transforms URL
		await coordinator.add(URLTransformingStub(transformedURL: transformedURL))

		let result = try await coordinator.process(testURL)

		#expect(result == transformedURL)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator throws error when middleware throws`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add middleware that throws error
		await coordinator.add(ErrorThrowingStub())

		do {
			_ = try await coordinator.process(testURL)
			#expect(Bool(false), "Expected error to be thrown")
		} catch {
			#expect(error is DeepLinkError)
		}
	}

	@Test
	func `DeepLinkMiddlewareCoordinator removes middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add middleware
		let middleware = MiddlewareSpy()
		await coordinator.add(middleware)

		// Remove middleware
		await coordinator.remove(MiddlewareSpy.self)

		// Should not process through middleware
		let result = try await coordinator.process(testURL)

		#expect(result == testURL)
		#expect(middleware.requests.isEmpty)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator removes all middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add multiple middleware
		let middleware1 = MiddlewareSpy()
		let middleware2 = MiddlewareSpy()
		await coordinator.add(middleware1)
		await coordinator.add(middleware2)

		// Remove all middleware
		await coordinator.removeAll()

		// Should not process through middleware
		let result = try await coordinator.process(testURL)

		#expect(result == testURL)
		#expect(middleware1.requests.isEmpty)
		#expect(middleware2.requests.isEmpty)
	}

	// MARK: - Logging Middleware Tests

	@Test
	func `LoggingMiddleware logs URL information`() async throws {
		let testURL = try #require(URL(string: "testapp://profile?userId=123"))
		let middleware = LoggingMiddleware()

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	// MARK: - Analytics Middleware Tests

	@Test
	func `AnalyticsMiddleware tracks deep link events`() async throws {
		let testURL = try #require(URL(string: "testapp://product?productId=456"))
		let analyticsProvider = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsProvider)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
		#expect(analyticsProvider.trackedEvents.count == 1)
		#expect(analyticsProvider.trackedEvents[0].event == "deep_link_opened")
		#expect(analyticsProvider.trackedEvents[0].parameters["url"] as? String == testURL.absoluteString)
	}

	// MARK: - Rate Limit Middleware Tests

	@Test
	func `RateLimitMiddleware allows requests within limit`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 5,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Make 3 requests (within limit)
		for _ in 0 ..< 3 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}
	}

	@Test
	func `RateLimitMiddleware blocks requests exceeding limit`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let persistence = InMemoryRateLimitPersistence()
		let middleware = RateLimitMiddleware(
			maxRequests: 2,
			timeWindow: 60.0,
			persistence: persistence,
		)

		// Make 2 requests (within limit)
		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(2, 60.0))
		}
	}

	// MARK: - Authentication Middleware Tests

	@Test
	func `AuthenticationMiddleware allows requests for unprotected hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://public"))
		let authProvider = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authProvider,
			protectedHosts: ["protected"],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware allows requests for protected hosts when authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authProvider = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authProvider,
			protectedHosts: ["protected"],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware blocks requests for protected hosts when not authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authProvider = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authProvider,
			protectedHosts: ["protected"],
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("protected"))
		}
	}

	// MARK: - Security Middleware Tests

	@Test
	func `SecurityMiddleware allows requests with allowed schemes`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let middleware = SecurityMiddleware(
			allowedSchemes: ["testapp"],
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
			allowedHosts: ["allowed"],
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

	// MARK: - URL Transformation Middleware Tests

	@Test
	func `URLTransformationMiddleware transforms URLs`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://transformed"))
		let transformer = URLTransformerStub(transformedURL: transformedURL)
		let middleware = URLTransformationMiddleware(transformer: transformer)

		let result = try await middleware.intercept(testURL)

		#expect(result == transformedURL)
	}

	@Test
	func `URLNormalizationTransformer normalizes URLs`() throws {
		let testURL = try #require(URL(string: "testapp://test//path?param1=value1&param2="))
		let transformer = URLNormalizationTransformer()

		let result = try transformer.transform(testURL)

		#expect(result.path == "/path")
		#expect(result.query?.contains("param1=value1") == true)
		#expect(result.query?.contains("param2=") == false)
	}

	// MARK: - Advanced Middleware Tests

	@Test
	func `AdvancedDeepLinkMiddleware provides full control over processing`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		// Add advanced middleware that transforms URL
		let advancedMiddleware = try AdvancedMiddlewareSpy(transformedURL: #require(URL(string: "testapp://advanced")))
		await coordinator.add(advancedMiddleware)

		let result = try await coordinator.process(testURL)

		#expect(result == URL(string: "testapp://advanced"))
	}

	// MARK: - Test Helpers

	// MARK: - Dummies

	private final class DummyMiddleware: DeepLinkMiddleware {
		func intercept(_: URL) async throws -> URL? {
			nil
		}
	}

	// MARK: - Stubs

	private final class MiddlewareStub: DeepLinkMiddleware {
		private let result: URL?

		init(result: URL?) {
			self.result = result
		}

		func intercept(_: URL) async throws -> URL? {
			result
		}
	}

	private final class ErrorThrowingStub: DeepLinkMiddleware {
		private let error: Error

		init(error: Error = DeepLinkError.handlerError("Test error")) {
			self.error = error
		}

		func intercept(_: URL) async throws -> URL? {
			throw error
		}
	}

	private final class URLTransformingStub: DeepLinkMiddleware {
		private let transformedURL: URL

		init(transformedURL: URL) {
			self.transformedURL = transformedURL
		}

		func intercept(_: URL) async throws -> URL? {
			transformedURL
		}
	}

	private final class URLTransformerStub: URLTransformer {
		private let transformedURL: URL

		init(transformedURL: URL) {
			self.transformedURL = transformedURL
		}

		func transform(_: URL) throws -> URL {
			transformedURL
		}
	}

	// MARK: - Spies

	private final class MiddlewareSpy: DeepLinkMiddleware, @unchecked Sendable {
		private(set) var requests = [URL]()

		func intercept(_ url: URL) async throws -> URL? {
			requests.append(url)
			return url
		}
	}

	private final class OrderTrackingSpy: DeepLinkMiddleware, @unchecked Sendable {
		private let id: String
		private(set) var requests = [URL]()
		private(set) var callTimes = [Date]()

		init(id: String) {
			self.id = id
		}

		func intercept(_ url: URL) async throws -> URL? {
			requests.append(url)
			callTimes.append(Date())
			return url
		}

		var wasCalled: Bool {
			!requests.isEmpty
		}

		func calledBefore(_ other: OrderTrackingSpy) -> Bool {
			guard let selfTime = callTimes.first, let otherTime = other.callTimes.first else {
				return false
			}
			return selfTime < otherTime
		}
	}

	private final class AdvancedMiddlewareSpy: AdvancedDeepLinkMiddleware, @unchecked Sendable {
		private let transformedURL: URL
		private(set) var requests = [URL]()

		init(transformedURL: URL) {
			self.transformedURL = transformedURL
		}

		func intercept(_ url: URL) async -> MiddlewareResult {
			requests.append(url)
			return .transform(transformedURL)
		}

		var wasCalled: Bool {
			!requests.isEmpty
		}
	}
}
