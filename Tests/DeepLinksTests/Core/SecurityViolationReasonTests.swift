//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct SecurityViolationReasonTests {
	@Test(arguments: [
		("Userinfo is not allowed", SecurityViolationReason.userinfo),
		("Control characters are not allowed", .controlCharacters),
		("Invisible formatting characters are not allowed", .invisibleCharacters),
		("Path traversal is not allowed", .pathTraversal),
		("Malformed percent-encoding", .malformedEncoding),
		("Malformed host", .malformedHost),
		("Missing host", .missingHost),
		("Invalid URL path format", .invalidPath),
		("Unauthorized scheme", .unauthorizedScheme),
		("Unauthorized host", .unauthorizedHost),
		("Source not allowed", .unauthorizedSource),
		("URL exceeds maximum length", .inputLimitExceeded),
		("Too many query parameters", .inputLimitExceeded),
		("Query parameter value exceeds maximum length", .inputLimitExceeded),
		("Duplicate query parameter", .duplicateParameter),
		("Replayed deep link", .replayedLink),
		("Too many pending confirmations", .tooManyPendingPrompts),
		("Invalid blocked pattern", .invalidConfiguration),
		("Missing link signature", .missingSignature),
		("Route requires a signed link", .missingSignature),
		("Invalid link signature", .invalidSignature),
		("Missing link expiry", .invalidExpiry),
		("Invalid link expiry", .invalidExpiry),
		("Signed link lifetime too long", .invalidExpiry),
		("Expired signed link", .expiredLink),
		("Missing link nonce", .missingNonce),
		("Signed link already used", .reusedNonce),
		("Signing key too short", .invalidConfiguration),
		("Could not sign link", .signingFailed),
	])
	func `every built-in reason string maps to its case`(message: String, reason: SecurityViolationReason) {
		#expect(DeepLinkError.securityViolation(message).securityViolationReason == reason)
	}

	@Test
	func `the public reason constants map to their cases`() {
		#expect(DeepLinkError.securityViolation(SignedLinkMiddleware.missingSignatureReason).securityViolationReason == .missingSignature)
		#expect(DeepLinkError.securityViolation(SignedLinkMiddleware.reusedNonceReason).securityViolationReason == .reusedNonce)
		#expect(DeepLinkError.securityViolation(SignedLinkMiddleware.expiredReason).securityViolationReason == .expiredLink)
		#expect(DeepLinkError.securityViolation(ConfirmationMiddleware.tooManyPendingPromptsReason).securityViolationReason == .tooManyPendingPrompts)
		#expect(DeepLinkError.securityViolation(SignedRouteGuard<TestRoute>.unsignedRouteReason).securityViolationReason == .missingSignature)
	}

	@Test
	func `a custom reason string is other`() {
		#expect(DeepLinkError.securityViolation("Payments require a Universal Link").securityViolationReason == .other)
	}

	@Test
	func `errors that are not security violations have no reason`() throws {
		#expect(try DeepLinkError.blockedURL(#require(URL(string: "myapp://a"))).securityViolationReason == nil)
		#expect(DeepLinkError.missingRequiredConfiguration("routing").securityViolationReason == nil)
	}

	@Test
	func `the canonicalizer reports userinfo by reason`() throws {
		let url = try #require(URL(string: "https://trusted.com@evil.com"))

		#expect {
			try URLCanonicalizer().canonicalize(url)
		} throws: { error in
			(error as? DeepLinkError)?.securityViolationReason == .userinfo
		}
	}

	@Test
	func `an invalid blocked pattern is reported as a configuration error`() {
		#expect {
			try caseInsensitiveRegex(pattern: "(", options: [])
		} throws: { error in
			(error as? DeepLinkError)?.securityViolationReason == .invalidConfiguration
		}
	}
}
