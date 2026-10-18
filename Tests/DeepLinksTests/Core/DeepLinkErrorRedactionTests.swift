//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkErrorRedactionTests {
	private static let sensitiveURL = URL(string: "https://example.com/reset?token=abc123&lang=en")!
	private static let redactedURL = "https://example.com/reset?token=REDACTED&lang=en"

	@Test(arguments: [
		(DeepLinkError.invalidURL(sensitiveURL), "Invalid URL: \(redactedURL)"),
		(.routeNotFound(sensitiveURL), "No route found for URL: \(redactedURL)"),
		(.unauthorizedAccess(sensitiveURL), "Unauthorized access to: \(redactedURL)"),
		(.blockedURL(sensitiveURL), "Blocked URL: \(redactedURL)"),
		(.confirmationDenied(sensitiveURL), "Confirmation denied for URL: \(redactedURL)"),
		(.parsingFailed(url: sensitiveURL, underlyingErrors: []), "Parsing failed for URL: \(redactedURL)"),
	])
	func `redactedDescription redacts URLs carried by the error`(error: DeepLinkError, expected: String) {
		#expect(error.redactedDescription == expected)
	}

	@Test
	func `redactedDescription of a huge attacker-controlled host is bounded`() {
		let error = DeepLinkError.unsupportedHost(String(repeating: "a", count: 100_000))

		#expect(error.redactedDescription.unicodeScalars.count <= URLRedactor.maximumRedactedTextLength + URLRedactor.truncationMarker.unicodeScalars.count)
	}

	@Test
	func `unredactedDescription keeps the full URL`() {
		let error = DeepLinkError.invalidURL(Self.sensitiveURL)

		#expect(error.unredactedDescription == "Invalid URL: \(Self.sensitiveURL.absoluteString)")
	}

	@Test
	func `errorDescription and localizedDescription are redacted by default`() {
		let error = DeepLinkError.invalidURL(Self.sensitiveURL)

		#expect(error.errorDescription == error.redactedDescription)
		#expect(error.localizedDescription == error.redactedDescription)
		#expect(error.errorDescription?.contains("REDACTED") == true)
		#expect(error.errorDescription != error.unredactedDescription)
	}

	@Test
	func `unredactedDescription keeps nested framework errors whole`() {
		let error = DeepLinkError.handlerError(message: "failed", underlyingError: DeepLinkError.invalidURL(Self.sensitiveURL))

		#expect(error.unredactedDescription == "Handler error: failed: Invalid URL: \(Self.sensitiveURL.absoluteString)")
	}

	@Test
	func `redactedDescription redacts the value of a sensitive parameter`() {
		let error = DeepLinkError.invalidParameterValue(name: "otp", value: "123456")

		#expect(error.redactedDescription == "Invalid value 'REDACTED' for parameter: otp")
	}

	@Test
	func `redactedDescription redacts the value of any parameter`() {
		let error = DeepLinkError.invalidParameterValue(name: "page", value: "jane@example.com")

		#expect(error.redactedDescription == "Invalid value 'REDACTED' for parameter: page")
	}

	@Test(arguments: [
		(
			DeepLinkError.handlerError(message: "Could not open https://x.com/cb?token=abc now", underlyingError: nil),
			"Handler error: Could not open https://x.com/cb?token=REDACTED now",
		),
		(.securityViolation("Rejected myapp://login?otp=123456"), "Security violation: Rejected myapp://login?otp=REDACTED"),
		(.unsupportedHost("https://user:pw@evil.com"), "Unsupported URL host: https://REDACTED@evil.com"),
		(.missingRequiredConfiguration("see https://x.com/?key=k1"), "Missing required configuration: see https://x.com/?key=REDACTED"),
		(
			.handlerError(message: "save failed for myapp://a?code=9", underlyingError: ForeignError()),
			"Handler error: save failed for myapp://a?code=REDACTED: ForeignError",
		),
	])
	func `redactedDescription redacts URLs embedded in free-form text`(error: DeepLinkError, expected: String) {
		#expect(error.redactedDescription == expected)
	}

	@Test(arguments: [
		DeepLinkError.unsupportedScheme("ftp"),
		.unsupportedHost("evil.com"),
		.missingRequiredParameter("id"),
		.missingRequiredConfiguration("routing"),
		.rateLimitExceeded(maxRequests: 5, timeWindow: 60),
		.securityViolation("Missing host"),
		.handlerError(message: "boom", underlyingError: nil),
	])
	func `redactedDescription matches errorDescription for cases without sensitive payloads`(error: DeepLinkError) {
		#expect(error.redactedDescription == error.errorDescription)
	}

	@Test
	func `redactedDescription redacts nested framework errors and hides foreign error text`() {
		let error = DeepLinkError.parsingFailed(
			url: Self.sensitiveURL,
			underlyingErrors: [DeepLinkError.blockedURL(Self.sensitiveURL), ForeignError()],
		)

		#expect(error.redactedDescription
			== "Parsing failed for URL: \(Self.redactedURL); Blocked URL: \(Self.redactedURL); ForeignError")
	}

	@Test
	func `redactedDescription replaces a foreign underlying handler error with its type name`() {
		let error = DeepLinkError.handlerError(message: "save failed", underlyingError: ForeignError())

		#expect(error.redactedDescription == "Handler error: save failed: ForeignError")
	}

	@Test
	func `redactedDescription accepts a custom redactor`() throws {
		let url = try #require(URL(string: "myapp://shop?promo=SUMMER"))
		let error = DeepLinkError.routeNotFound(url)

		#expect(error.redactedDescription(using: URLRedactor(sensitiveKeys: ["promo"]))
			== "No route found for URL: myapp://shop?promo=REDACTED")
	}
}

private struct ForeignError: LocalizedError {
	var errorDescription: String? {
		"secret user@example.com leaked"
	}
}
