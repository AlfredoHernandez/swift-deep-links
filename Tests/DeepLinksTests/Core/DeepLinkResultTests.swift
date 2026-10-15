//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkResultTests {
	private static let sampleURL = URL(string: "myapp://profile")!

	// MARK: - wasSuccessful truth table

	@Test(arguments: Self.wasSuccessfulCases)
	func `wasSuccessful reflects middleware, errors, and failedRoutes`(scenario: WasSuccessfulScenario) {
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: scenario.processedURL,
			routes: scenario.routes,
			executionTime: 0,
			errors: scenario.errors,
			successfulRoutes: scenario.successfulRoutes,
			failedRoutes: scenario.failedRoutes,
		)

		#expect(result.wasSuccessful == scenario.expected)
	}

	// MARK: - Convenience accessors

	@Test
	func `wasStoppedByMiddleware is true when processedURL is nil`() {
		let stopped = makeResult(processedURL: nil)
		let passed = makeResult(processedURL: Self.sampleURL)

		#expect(stopped.wasStoppedByMiddleware == true)
		#expect(passed.wasStoppedByMiddleware == false)
	}

	@Test
	func `hasRoutes reflects the routes array`() {
		#expect(makeResult(routes: []).hasRoutes == false)
		#expect(makeResult(routes: [.route1]).hasRoutes == true)
		#expect(makeResult(routes: [.route1, .route2]).hasRoutes == true)
	}

	@Test
	func `hasErrors reflects the errors array`() {
		#expect(makeResult(errors: []).hasErrors == false)
		#expect(makeResult(errors: [DeepLinkError.unsupportedScheme("ftp")]).hasErrors == true)
	}

	@Test
	func `firstError returns the first entry in errors or nil`() {
		let first = DeepLinkError.unsupportedScheme("ftp")
		let second = DeepLinkError.handlerError(message: "later", underlyingError: nil)

		#expect(makeResult(errors: []).firstDeepLinkError == nil)
		#expect(makeResult(errors: [first]).firstDeepLinkError == first)
		#expect(makeResult(errors: [first, second]).firstDeepLinkError == first)
	}

	// MARK: - summary

	@Test
	func `summary calls out middleware-stopped processing`() {
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: nil,
			routes: [],
			executionTime: 0.05,
		)

		#expect(result.summary == "Processing stopped by middleware")
	}

	@Test
	func `summary reports successful processing with route count and timing`() {
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: Self.sampleURL,
			routes: [.route1, .route2],
			executionTime: 0.043,
			errors: [],
			successfulRoutes: 2,
			failedRoutes: 0,
		)

		#expect(result.summary == "Successfully processed 2 route(s) in 0.043s")
	}

	@Test
	func `summary reports partial failures with error count`() {
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: Self.sampleURL,
			routes: [.route1, .route2, .route3],
			executionTime: 0.156,
			errors: [DeepLinkError.handlerError(message: "boom", underlyingError: nil)],
			successfulRoutes: 2,
			failedRoutes: 1,
		)

		#expect(result.summary == "Processed 2/3 routes with 1 error(s) in 0.156s")
	}

	@Test
	func `summary reports successful processing even when zero routes matched`() {
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: Self.sampleURL,
			routes: [],
			executionTime: 0.020,
			errors: [],
			successfulRoutes: 0,
			failedRoutes: 0,
		)

		#expect(result.summary == "Successfully processed 0 route(s) in 0.020s")
	}

	// MARK: - Helpers

	private func makeResult(
		processedURL: URL? = DeepLinkResultTests.sampleURL,
		routes: [TestRoute] = [],
		errors: [any Error] = [],
	) -> DeepLinkResult<TestRoute> {
		DeepLinkResult<TestRoute>(
			originalURL: Self.sampleURL,
			processedURL: processedURL,
			routes: routes,
			executionTime: 0,
			errors: errors,
		)
	}

	// MARK: - Parameterised truth table

	struct WasSuccessfulScenario: CustomStringConvertible {
		let name: String
		let processedURL: URL?
		let routes: [TestRoute]
		let errors: [any Error]
		let successfulRoutes: Int
		let failedRoutes: Int
		let expected: Bool

		var description: String {
			name
		}
	}

	fileprivate static let wasSuccessfulCases: [WasSuccessfulScenario] = {
		let url = URL(string: "myapp://profile")!
		return [
			WasSuccessfulScenario(
				name: "stopped by middleware",
				processedURL: nil,
				routes: [],
				errors: [],
				successfulRoutes: 0,
				failedRoutes: 0,
				expected: false,
			),
			WasSuccessfulScenario(
				name: "all routes succeeded",
				processedURL: url,
				routes: [.route1, .route2],
				errors: [],
				successfulRoutes: 2,
				failedRoutes: 0,
				expected: true,
			),
			WasSuccessfulScenario(
				name: "no routes and no errors",
				processedURL: url,
				routes: [],
				errors: [],
				successfulRoutes: 0,
				failedRoutes: 0,
				expected: true,
			),
			WasSuccessfulScenario(
				name: "partial failure with failedRoutes > 0",
				processedURL: url,
				routes: [.route1, .route2],
				errors: [DeepLinkError.handlerError(message: "boom", underlyingError: nil)],
				successfulRoutes: 1,
				failedRoutes: 1,
				expected: false,
			),
			WasSuccessfulScenario(
				name: "errors present but no failed routes",
				processedURL: url,
				routes: [.route1],
				errors: [DeepLinkError.unsupportedScheme("ftp")],
				successfulRoutes: 1,
				failedRoutes: 0,
				expected: false,
			),
		]
	}()
}
