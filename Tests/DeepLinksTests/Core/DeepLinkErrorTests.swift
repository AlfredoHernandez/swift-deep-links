//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkErrorTests {
	private static let sampleURL = URL(string: "myapp://host/path?q=1")!

	// MARK: - errorDescription

	@Test(arguments: errorDescriptionCases)
	func `errorDescription renders the expected message per case`(scenario: ErrorDescriptionScenario) {
		#expect(scenario.error.errorDescription == scenario.expected)
	}

	@Test
	func `errorDescription for parsingFailed joins underlying descriptions`() {
		let url = Self.sampleURL
		let error = DeepLinkError.parsingFailed(url: url, underlyingErrors: [
			DeepLinkError.missingRequiredParameter("userId"),
			DeepLinkError.unsupportedHost("settings"),
		])

		#expect(error.errorDescription == "Parsing failed for URL: \(url.absoluteString); "
			+ "Missing required parameter: userId; Unsupported URL host: settings")
	}

	@Test
	func `errorDescription for parsingFailed with no underlying errors omits the separator`() {
		let url = Self.sampleURL
		let error = DeepLinkError.parsingFailed(url: url, underlyingErrors: [])

		#expect(error.errorDescription == "Parsing failed for URL: \(url.absoluteString)")
	}

	@Test
	func `errorDescription for handlerError appends the underlying cause when present`() {
		let underlying = DeepLinkError.invalidURL(Self.sampleURL)
		let error = DeepLinkError.handlerError(message: "route failed", underlyingError: underlying)

		#expect(error.errorDescription == "Handler error: route failed: Invalid URL: \(Self.sampleURL.absoluteString)")
	}

	@Test
	func `errorDescription for handlerError without an underlying cause stays minimal`() {
		let error = DeepLinkError.handlerError(message: "route failed", underlyingError: nil)

		#expect(error.errorDescription == "Handler error: route failed")
	}

	// MARK: - Equatable

	@Test
	func `cases with the same payload compare equal`() {
		let url = Self.sampleURL

		#expect(DeepLinkError.invalidURL(url) == DeepLinkError.invalidURL(url))
		#expect(DeepLinkError.unsupportedScheme("https") == DeepLinkError.unsupportedScheme("https"))
		#expect(DeepLinkError.unsupportedHost("host") == DeepLinkError.unsupportedHost("host"))
		#expect(DeepLinkError.missingRequiredParameter("id") == DeepLinkError.missingRequiredParameter("id"))
		#expect(
			DeepLinkError.invalidParameterValue(name: "age", value: "x")
				== DeepLinkError.invalidParameterValue(name: "age", value: "x"),
		)
		#expect(DeepLinkError.routeNotFound(url) == DeepLinkError.routeNotFound(url))
		#expect(DeepLinkError.missingRequiredConfiguration("routing") == DeepLinkError.missingRequiredConfiguration("routing"))
		#expect(
			DeepLinkError.rateLimitExceeded(maxRequests: 10, timeWindow: 60)
				== DeepLinkError.rateLimitExceeded(maxRequests: 10, timeWindow: 60),
		)
		#expect(DeepLinkError.securityViolation("bad") == DeepLinkError.securityViolation("bad"))
		#expect(DeepLinkError.unauthorizedAccess(url) == DeepLinkError.unauthorizedAccess(url))
		#expect(DeepLinkError.blockedURL(url) == DeepLinkError.blockedURL(url))
		#expect(DeepLinkError.confirmationDenied(url) == DeepLinkError.confirmationDenied(url))
	}

	@Test
	func `different cases never compare equal`() {
		let url = Self.sampleURL
		#expect(DeepLinkError.invalidURL(url) != .routeNotFound(url))
		#expect(DeepLinkError.unsupportedScheme("a") != .unsupportedHost("a"))
		#expect(DeepLinkError.unauthorizedAccess(url) != .blockedURL(url))
		#expect(DeepLinkError.confirmationDenied(url) != .blockedURL(url))
	}

	@Test
	func `cases with differing payloads compare unequal`() throws {
		let url1 = try #require(URL(string: "myapp://a"))
		let url2 = try #require(URL(string: "myapp://b"))

		#expect(DeepLinkError.invalidURL(url1) != .invalidURL(url2))
		#expect(DeepLinkError.unsupportedScheme("a") != .unsupportedScheme("b"))
		#expect(
			DeepLinkError.invalidParameterValue(name: "a", value: "x")
				!= .invalidParameterValue(name: "a", value: "y"),
		)
		#expect(
			DeepLinkError.rateLimitExceeded(maxRequests: 10, timeWindow: 60)
				!= .rateLimitExceeded(maxRequests: 10, timeWindow: 30),
		)
	}

	@Test
	func `parsingFailed equality ignores underlying error payloads when counts match`() throws {
		let url = Self.sampleURL
		let sharedErrors: [any Error & Sendable] = [
			DeepLinkError.missingRequiredParameter("userId"),
			DeepLinkError.unsupportedHost("settings"),
		]
		let structurallyDivergentButSameCount: [any Error & Sendable] = try [
			DeepLinkError.missingRequiredParameter("someOtherParam"),
			DeepLinkError.routeNotFound(#require(URL(string: "myapp://completely-different"))),
		]

		#expect(
			DeepLinkError.parsingFailed(url: url, underlyingErrors: sharedErrors)
				== .parsingFailed(url: url, underlyingErrors: sharedErrors),
		)
		#expect(
			DeepLinkError.parsingFailed(url: url, underlyingErrors: sharedErrors)
				== .parsingFailed(url: url, underlyingErrors: structurallyDivergentButSameCount),
		)
	}

	@Test
	func `parsingFailed equality distinguishes underlying error counts`() {
		let url = Self.sampleURL
		let oneError: [any Error & Sendable] = [DeepLinkError.missingRequiredParameter("userId")]
		let twoErrors: [any Error & Sendable] = [
			DeepLinkError.missingRequiredParameter("userId"),
			DeepLinkError.unsupportedHost("settings"),
		]

		#expect(
			DeepLinkError.parsingFailed(url: url, underlyingErrors: oneError)
				!= .parsingFailed(url: url, underlyingErrors: twoErrors),
		)
		#expect(
			DeepLinkError.parsingFailed(url: url, underlyingErrors: [])
				!= .parsingFailed(url: url, underlyingErrors: oneError),
		)
	}

	@Test
	func `parsingFailed equality compares URL`() throws {
		let urlA = try #require(URL(string: "myapp://a"))
		let urlB = try #require(URL(string: "myapp://b"))
		let errors: [any Error & Sendable] = [DeepLinkError.missingRequiredParameter("userId")]

		#expect(
			DeepLinkError.parsingFailed(url: urlA, underlyingErrors: errors)
				!= .parsingFailed(url: urlB, underlyingErrors: errors),
		)
	}

	@Test
	func `handlerError equality ignores underlying error payloads when nil-ness matches`() {
		let underlying = DeepLinkError.invalidURL(Self.sampleURL)
		let differentUnderlying = DeepLinkError.unsupportedHost("other")

		#expect(
			DeepLinkError.handlerError(message: "m", underlyingError: underlying)
				== .handlerError(message: "m", underlyingError: underlying),
		)
		#expect(
			DeepLinkError.handlerError(message: "m", underlyingError: underlying)
				== .handlerError(message: "m", underlyingError: differentUnderlying),
		)
		#expect(
			DeepLinkError.handlerError(message: "m", underlyingError: underlying)
				!= .handlerError(message: "different message", underlyingError: underlying),
		)
	}

	@Test
	func `handlerError treats nil underlying as distinct from any non-nil underlying`() {
		let underlying = DeepLinkError.invalidURL(Self.sampleURL)

		#expect(
			DeepLinkError.handlerError(message: "m", underlyingError: nil)
				!= .handlerError(message: "m", underlyingError: underlying),
		)
		#expect(
			DeepLinkError.handlerError(message: "m", underlyingError: nil)
				== .handlerError(message: "m", underlyingError: nil),
		)
	}
}

// MARK: - Parameterized Scenarios

struct ErrorDescriptionScenario: CustomStringConvertible {
	let name: String
	let error: DeepLinkError
	let expected: String

	var description: String {
		name
	}
}

let errorDescriptionCases: [ErrorDescriptionScenario] = {
	let url = URL(string: "myapp://host/path?q=1")!
	return [
		ErrorDescriptionScenario(
			name: "invalidURL",
			error: .invalidURL(url),
			expected: "Invalid URL: \(url.absoluteString)",
		),
		ErrorDescriptionScenario(
			name: "unsupportedScheme",
			error: .unsupportedScheme("ftp"),
			expected: "Unsupported URL scheme: ftp",
		),
		ErrorDescriptionScenario(
			name: "unsupportedHost",
			error: .unsupportedHost("unknown"),
			expected: "Unsupported URL host: unknown",
		),
		ErrorDescriptionScenario(
			name: "missingRequiredParameter",
			error: .missingRequiredParameter("userId"),
			expected: "Missing required parameter: userId",
		),
		ErrorDescriptionScenario(
			name: "invalidParameterValue",
			error: .invalidParameterValue(name: "age", value: "abc"),
			expected: "Invalid value 'abc' for parameter: age",
		),
		ErrorDescriptionScenario(
			name: "routeNotFound",
			error: .routeNotFound(url),
			expected: "No route found for URL: \(url.absoluteString)",
		),
		ErrorDescriptionScenario(
			name: "missingRequiredConfiguration",
			error: .missingRequiredConfiguration("handler"),
			expected: "Missing required configuration: handler",
		),
		ErrorDescriptionScenario(
			name: "rateLimitExceeded",
			error: .rateLimitExceeded(maxRequests: 10, timeWindow: 60),
			expected: "Rate limit exceeded: 10 requests in 60.0 seconds",
		),
		ErrorDescriptionScenario(
			name: "securityViolation",
			error: .securityViolation("blocked"),
			expected: "Security violation: blocked",
		),
		ErrorDescriptionScenario(
			name: "unauthorizedAccess",
			error: .unauthorizedAccess(url),
			expected: "Unauthorized access to: \(url.absoluteString)",
		),
		ErrorDescriptionScenario(
			name: "blockedURL",
			error: .blockedURL(url),
			expected: "Blocked URL: \(url.absoluteString)",
		),
		ErrorDescriptionScenario(
			name: "confirmationDenied",
			error: .confirmationDenied(url),
			expected: "Confirmation denied for URL: \(url.absoluteString)",
		),
	]
}()
