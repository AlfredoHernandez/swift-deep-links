//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Errors that can occur during deep link processing.
///
/// This enum provides comprehensive error handling for all aspects of deep link
/// processing, from URL validation to route execution. All errors conform to
/// `Equatable` for easy testing and `LocalizedError` for user-friendly descriptions.
///
/// ## Error Types
///
/// - `invalidURL`: The provided URL is malformed or cannot be parsed
/// - `unsupportedScheme`: The URL scheme is not supported by the app
/// - `unsupportedHost`: The URL host is not recognized by any parser
/// - `missingRequiredParameter`: A required query parameter is missing
/// - `invalidParameterValue`: A parameter value is invalid or cannot be parsed
/// - `routeNotFound`: No parser was able to handle the URL
/// - `handlerError`: An error occurred during route execution
public enum DeepLinkError: Error, Equatable, LocalizedError {
	/// The provided URL is malformed or cannot be parsed
	case invalidURL(URL)

	/// The URL scheme is not supported by the app
	case unsupportedScheme(String)

	/// The URL host is not recognized by any parser
	case unsupportedHost(String)

	/// A required query parameter is missing
	case missingRequiredParameter(String)

	/// A parameter value is invalid or cannot be parsed
	case invalidParameterValue(String, String)

	/// No parser was able to handle the URL
	case routeNotFound(String)

	/// An error occurred during route execution
	case handlerError(String)

	/// Required configuration is missing
	case missingRequiredConfiguration(String)

	/// Too many requests in a short time period
	case rateLimitExceeded(Int, TimeInterval)

	/// A security policy was violated
	case securityViolation(String)

	/// Access was denied due to insufficient permissions
	case unauthorizedAccess(String)

	/// The URL is blocked by security policies
	case blockedURL(String)

	/// Provides a human-readable description of the error.
	///
	/// This implementation returns a descriptive string representation of the error case,
	/// which is useful for logging, debugging, and user-facing error messages.
	public var errorDescription: String? {
		switch self {
		case let .invalidURL(url):
			"Invalid URL: \(url.absoluteString)"

		case let .unsupportedScheme(scheme):
			"Unsupported URL scheme: \(scheme)"

		case let .unsupportedHost(host):
			"Unsupported URL host: \(host)"

		case let .missingRequiredParameter(parameter):
			"Missing required parameter: \(parameter)"

		case let .invalidParameterValue(parameter, value):
			"Invalid value '\(value)' for parameter: \(parameter)"

		case let .routeNotFound(host):
			"No route found for host: \(host)"

		case let .handlerError(message):
			"Handler error: \(message)"

		case let .missingRequiredConfiguration(component):
			"Missing required configuration: \(component)"

		case let .rateLimitExceeded(count, interval):
			"Rate limit exceeded: \(count) requests in \(interval) seconds"

		case let .securityViolation(reason):
			"Security violation: \(reason)"

		case let .unauthorizedAccess(resource):
			"Unauthorized access to: \(resource)"

		case let .blockedURL(url):
			"Blocked URL: \(url)"
		}
	}
}
