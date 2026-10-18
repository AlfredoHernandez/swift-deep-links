//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
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

		await coordinator.add(MiddlewareSpy())

		let result = try await coordinator.process(url: testURL)

		#expect(result == testURL)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator stops processing when middleware returns nil`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		await coordinator.add(MiddlewareStub(result: nil))

		let result = try await coordinator.process(url: testURL)

		#expect(result == nil)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator processes middleware in order`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		let firstMiddleware = OrderTrackingSpy(id: "first")
		let secondMiddleware = OrderTrackingSpy(id: "second")

		await coordinator.add(firstMiddleware)
		await coordinator.add(secondMiddleware)

		_ = try await coordinator.process(url: testURL)

		#expect(firstMiddleware.wasCalled)
		#expect(secondMiddleware.wasCalled)

		#expect(try #require(firstMiddleware.callTimes.first) < secondMiddleware.callTimes.first!)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator transforms URL through middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://transformed"))

		await coordinator.add(URLTransformingStub(transformedURL: transformedURL))

		let result = try await coordinator.process(url: testURL)

		#expect(result == transformedURL)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator throws error when middleware throws`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		await coordinator.add(ErrorThrowingStub())

		do {
			_ = try await coordinator.process(url: testURL)
			#expect(Bool(false), "Expected error to be thrown")
		} catch {
			#expect(error is DeepLinkError)
		}
	}

	@Test
	func `DeepLinkMiddlewareCoordinator removes middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		let middleware = MiddlewareSpy()
		await coordinator.add(middleware)

		await coordinator.remove(MiddlewareSpy.self)

		let result = try await coordinator.process(url: testURL)

		#expect(result == testURL)
		#expect(middleware.requests.isEmpty)
	}

	@Test
	func `DeepLinkMiddlewareCoordinator removes all middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		let middleware1 = MiddlewareSpy()
		let middleware2 = MiddlewareSpy()
		await coordinator.add(middleware1)
		await coordinator.add(middleware2)

		await coordinator.removeAll()

		let result = try await coordinator.process(url: testURL)

		#expect(result == testURL)
		#expect(middleware1.requests.isEmpty)
		#expect(middleware2.requests.isEmpty)
	}

	// MARK: - Logging Middleware Tests

	@Test
	func `LoggingMiddleware logs URL information`() async throws {
		let testURL = try #require(URL(string: "testapp://profile?userId=123"))
		let middleware = LoggingMiddleware()

		let result = try await middleware.intercept(url: testURL)

		#expect(result == testURL)
	}

	// MARK: - Analytics Middleware Tests

	@Test
	func `AnalyticsMiddleware tracks deep link events`() async throws {
		let testURL = try #require(URL(string: "testapp://product?productId=456"))
		let analyticsProvider = AnalyticsProviderSpy()
		let middleware = AnalyticsMiddleware(analyticsProvider: analyticsProvider)

		let result = try await middleware.intercept(url: testURL)

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

		for _ in 0 ..< 3 {
			let result = try await middleware.intercept(url: testURL)
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

		for _ in 0 ..< 2 {
			let result = try await middleware.intercept(url: testURL)
			#expect(result == testURL)
		}

		// Third request should be blocked
		do {
			_ = try await middleware.intercept(url: testURL)
			#expect(Bool(false), "Expected rate limit error")
		} catch let error as DeepLinkError {
			#expect(error == .rateLimitExceeded(maxRequests: 2, timeWindow: 60.0))
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

		let result = try await middleware.intercept(url: testURL)

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

		let result = try await middleware.intercept(url: testURL)

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
			_ = try await middleware.intercept(url: testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess(testURL))
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
			allowedHosts: ["allowed"],
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

	// MARK: - URL Transformation Middleware Tests

	@Test
	func `URLTransformationMiddleware transforms URLs`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://transformed"))
		let transformer = URLTransformerStub(transformedURL: transformedURL)
		let middleware = URLTransformationMiddleware(transformer: transformer)

		let result = try await middleware.intercept(url: testURL)

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

	// MARK: - Middleware Protocol Coverage

	@Test
	func `middleware can transform the URL for downstream middleware`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://advanced"))

		await coordinator.add(URLTransformingStub(transformedURL: transformedURL))

		let result = try await coordinator.process(url: testURL)

		#expect(result == transformedURL)
	}

	@Test
	func `middleware can halt processing by returning nil`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		await coordinator.add(MiddlewareStub(result: nil))

		let result = try await coordinator.process(url: testURL)

		#expect(result == nil)
	}

	@Test
	func `middleware can halt processing by throwing an error`() async throws {
		let coordinator = DeepLinkMiddlewareCoordinator()
		let testURL = try #require(URL(string: "testapp://test"))

		await coordinator.add(ErrorThrowingStub())

		await #expect(throws: DeepLinkError.self) {
			try await coordinator.process(url: testURL)
		}
	}

	// MARK: - Stubs

	private final class MiddlewareStub: DeepLinkMiddleware {
		private let result: URL?

		init(result: URL?) {
			self.result = result
		}

		func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
			result.map(request.replacingURL)
		}
	}

	private final class ErrorThrowingStub: DeepLinkMiddleware {
		private let error: Error

		init(error: Error = DeepLinkError.handlerError(message: "Test error", underlyingError: nil)) {
			self.error = error
		}

		func intercept(_: DeepLinkRequest) async throws -> DeepLinkRequest? {
			throw error
		}
	}

	private final class URLTransformingStub: DeepLinkMiddleware {
		private let transformedURL: URL

		init(transformedURL: URL) {
			self.transformedURL = transformedURL
		}

		func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
			request.replacingURL(transformedURL)
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

		func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
			requests.append(request.url)
			return request
		}
	}

	private final class OrderTrackingSpy: DeepLinkMiddleware, @unchecked Sendable {
		private let id: String
		private(set) var requests = [URL]()
		private(set) var callTimes = [Date]()

		init(id: String) {
			self.id = id
		}

		func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
			requests.append(request.url)
			callTimes.append(Date())
			return request
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
}
