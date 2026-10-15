//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Why a link was rejected with ``DeepLinkError/securityViolation(_:)``, for
/// code that branches on the cause instead of comparing reason strings.
///
/// Read it with ``DeepLinkError/securityViolationReason``. Built-in middleware
/// keeps throwing the same reason strings, so existing comparisons keep
/// working. The reason is derived from the string, so a custom middleware
/// throwing one of the built-in strings gets that case; any other string
/// maps to ``other``.
///
/// Minor releases may add cases as built-in checks grow, so a `switch` over
/// this enum should end with a `default` branch.
///
/// ```swift
/// if result.firstDeepLinkError?.securityViolationReason == .expiredLink {
///     showLinkExpiredBanner()
/// }
/// ```
public enum SecurityViolationReason: Sendable, Hashable, CaseIterable {
	/// The URL carries userinfo (`https://trusted.com@evil.com`).
	case userinfo

	/// The URL contains control characters in some percent-decoded form.
	case controlCharacters

	/// The URL contains Unicode format or line/paragraph separator characters.
	case invisibleCharacters

	/// The path has a `..` segment in some percent-decoded form.
	case pathTraversal

	/// Percent-encoding is not valid UTF-8 or is nested too deeply.
	case malformedEncoding

	/// The host decodes to a delimiter or other non-host character.
	case malformedHost

	/// A host is required and the URL has none.
	case missingHost

	/// The path does not have the form the strategy requires.
	case invalidPath

	/// The scheme is not allowed.
	case unauthorizedScheme

	/// The host is not allowed.
	case unauthorizedHost

	/// The link arrived through a source that is not allowed.
	case unauthorizedSource

	/// The URL exceeds a ``DeepLinkInputLimits`` length or count limit.
	case inputLimitExceeded

	/// The query repeats a parameter and duplicates are rejected.
	case duplicateParameter

	/// The link or route requires a signature and the link has none.
	case missingSignature

	/// The link's signature does not verify.
	case invalidSignature

	/// The signed link's expiry is missing, malformed or too far away.
	case invalidExpiry

	/// The signed link has expired.
	case expiredLink

	/// The signed link has no nonce and one is required.
	case missingNonce

	/// The signed link's nonce was already used.
	case reusedNonce

	/// ``ReplayProtectionMiddleware`` saw the link too recently.
	case replayedLink

	/// ``ConfirmationMiddleware`` already has as many links waiting as allowed.
	case tooManyPendingPrompts

	/// The middleware is misconfigured, for example with a blocked pattern
	/// that does not compile or a signing key that is too short.
	case invalidConfiguration

	/// A link could not be signed.
	case signingFailed

	/// A reason string this package does not throw, such as one from your
	/// own middleware.
	case other

	/// The case for a ``DeepLinkError/securityViolation(_:)`` reason string.
	init(message: String) {
		self = Self.casesByMessage[message] ?? .other
	}

	private static let casesByMessage: [String: SecurityViolationReason] = [
		SecurityViolationMessage.userinfo: .userinfo,
		SecurityViolationMessage.controlCharacters: .controlCharacters,
		SecurityViolationMessage.invisibleCharacters: .invisibleCharacters,
		SecurityViolationMessage.pathTraversal: .pathTraversal,
		SecurityViolationMessage.malformedEncoding: .malformedEncoding,
		SecurityViolationMessage.malformedHost: .malformedHost,
		SecurityViolationMessage.missingHost: .missingHost,
		SecurityViolationMessage.invalidPath: .invalidPath,
		SecurityViolationMessage.unauthorizedScheme: .unauthorizedScheme,
		SecurityViolationMessage.unauthorizedHost: .unauthorizedHost,
		SecurityViolationMessage.unauthorizedSource: .unauthorizedSource,
		SecurityViolationMessage.urlTooLong: .inputLimitExceeded,
		SecurityViolationMessage.tooManyQueryParameters: .inputLimitExceeded,
		SecurityViolationMessage.parameterValueTooLong: .inputLimitExceeded,
		SecurityViolationMessage.duplicateParameter: .duplicateParameter,
		SecurityViolationMessage.missingSignature: .missingSignature,
		SecurityViolationMessage.unsignedRoute: .missingSignature,
		SecurityViolationMessage.invalidSignature: .invalidSignature,
		SecurityViolationMessage.missingExpiry: .invalidExpiry,
		SecurityViolationMessage.invalidExpiry: .invalidExpiry,
		SecurityViolationMessage.lifetimeTooLong: .invalidExpiry,
		SecurityViolationMessage.expired: .expiredLink,
		SecurityViolationMessage.missingNonce: .missingNonce,
		SecurityViolationMessage.reusedNonce: .reusedNonce,
		SecurityViolationMessage.replayed: .replayedLink,
		SecurityViolationMessage.tooManyPendingPrompts: .tooManyPendingPrompts,
		SecurityViolationMessage.invalidBlockedPattern: .invalidConfiguration,
		SecurityViolationMessage.weakKey: .invalidConfiguration,
		SecurityViolationMessage.signingFailed: .signingFailed,
	]
}

public extension DeepLinkError {
	/// Why the link was rejected, for a ``securityViolation(_:)``; `nil` for
	/// every other error.
	var securityViolationReason: SecurityViolationReason? {
		guard case let .securityViolation(message) = self else { return nil }
		return SecurityViolationReason(message: message)
	}
}

/// The reason strings built-in components throw with
/// ``DeepLinkError/securityViolation(_:)``; each maps to one
/// ``SecurityViolationReason``.
enum SecurityViolationMessage {
	static let userinfo = "Userinfo is not allowed"
	static let controlCharacters = "Control characters are not allowed"
	static let invisibleCharacters = "Invisible formatting characters are not allowed"
	static let pathTraversal = "Path traversal is not allowed"
	static let malformedEncoding = "Malformed percent-encoding"
	static let malformedHost = "Malformed host"
	static let missingHost = "Missing host"
	static let invalidPath = "Invalid URL path format"
	static let unauthorizedScheme = "Unauthorized scheme"
	static let unauthorizedHost = "Unauthorized host"
	static let unauthorizedSource = "Source not allowed"
	static let urlTooLong = "URL exceeds maximum length"
	static let tooManyQueryParameters = "Too many query parameters"
	static let parameterValueTooLong = "Query parameter value exceeds maximum length"
	static let duplicateParameter = "Duplicate query parameter"
	static let missingSignature = "Missing link signature"
	static let unsignedRoute = "Route requires a signed link"
	static let invalidSignature = "Invalid link signature"
	static let missingExpiry = "Missing link expiry"
	static let invalidExpiry = "Invalid link expiry"
	static let lifetimeTooLong = "Signed link lifetime too long"
	static let expired = "Expired signed link"
	static let missingNonce = "Missing link nonce"
	static let reusedNonce = "Signed link already used"
	static let replayed = "Replayed deep link"
	static let tooManyPendingPrompts = "Too many pending confirmations"
	static let invalidBlockedPattern = "Invalid blocked pattern"
	static let weakKey = "Signing key too short"
	static let signingFailed = "Could not sign link"
}
