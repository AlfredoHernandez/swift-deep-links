//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Errors that can occur during deep link processing.
///
/// This enum provides typed error cases for every stage of deep link
/// processing, from URL validation through parser execution to route
/// handling. Cases carry the originating URL or parameter context so
/// callers do not have to log or re-derive it from surrounding state,
/// and propagate underlying errors when the framework wraps failures
/// from user-supplied parsers or handlers.
///
/// ## Error Types
///
/// - ``invalidURL(_:)`` – The URL is malformed.
/// - ``unsupportedScheme(_:)`` – The URL scheme is not allowed.
/// - ``unsupportedHost(_:)`` – The URL host is not allowed.
/// - ``missingRequiredParameter(_:)`` – A required query parameter is
///   missing.
/// - ``invalidParameterValue(name:value:)`` – A parameter value is
///   invalid or cannot be parsed.
/// - ``routeNotFound(_:)`` – No parser produced a route for the URL.
/// - ``parsingFailed(url:underlyingErrors:)`` – Every parser in the
///   chain threw; their errors are collected here.
/// - ``handlerError(message:underlyingError:)`` – A route handler
///   failed; the triggering error (if any) is preserved.
/// - ``missingRequiredConfiguration(_:)`` – A required coordinator
///   component was not configured.
/// - ``rateLimitExceeded(maxRequests:timeWindow:)`` – Too many requests
///   in the configured window.
/// - ``securityViolation(_:)`` – A security policy was violated.
/// - ``unauthorizedAccess(_:)`` – Access to the URL was denied.
/// - ``blockedURL(_:)`` – The URL is explicitly blocked.
/// - ``confirmationDenied(_:)`` – The user declined, or did not answer,
///   a confirmation prompt.
///
/// ## Equality
///
/// ``DeepLinkError`` conforms to `Equatable` so tests can assert on
/// specific cases. For the two cases that carry `any Error` payloads,
/// the comparison is **structural but not recursive**:
///
/// - ``parsingFailed(url:underlyingErrors:)`` compares the URL and the
///   number of underlying errors. The individual payloads are not
///   inspected.
/// - ``handlerError(message:underlyingError:)`` compares the message
///   and whether the underlying error is present (`nil` vs non-`nil`).
///   Two non-`nil` payloads are considered equal regardless of their
///   contents.
///
/// Callers who need full structural equality on the underlying errors
/// must unwrap and compare them explicitly. This keeps `==` total,
/// symmetric, and locale-independent.
public enum DeepLinkError: Error, Sendable, LocalizedError {
	/// The provided URL is malformed or cannot be parsed.
	case invalidURL(URL)

	/// The URL scheme is not supported by the app.
	case unsupportedScheme(String)

	/// The URL host is not recognized by any parser.
	case unsupportedHost(String)

	/// A required query parameter is missing.
	case missingRequiredParameter(String)

	/// A parameter value is invalid or cannot be parsed.
	///
	/// - Parameters:
	///   - name: The parameter name whose value failed validation.
	///   - value: The raw value that was rejected.
	case invalidParameterValue(name: String, value: String)

	/// No parser produced a route for the given URL.
	case routeNotFound(URL)

	/// Every parser in the chain threw while attempting to parse the URL.
	///
	/// - Parameters:
	///   - url: The URL that no parser could handle.
	///   - underlyingErrors: The ordered list of errors thrown by each
	///     attempted parser.
	case parsingFailed(url: URL, underlyingErrors: [any Error & Sendable])

	/// A route handler failed.
	///
	/// - Parameters:
	///   - message: Human-readable description of the failure scope.
	///   - underlyingError: The error the handler threw, if any.
	case handlerError(message: String, underlyingError: (any Error & Sendable)?)

	/// A required coordinator component was not configured.
	case missingRequiredConfiguration(String)

	/// Too many requests were processed in the configured time window.
	case rateLimitExceeded(maxRequests: Int, timeWindow: TimeInterval)

	/// A security policy was violated.
	case securityViolation(String)

	/// Access to the URL was denied due to insufficient permissions.
	case unauthorizedAccess(URL)

	/// The URL is blocked by security policies.
	case blockedURL(URL)

	/// The user declined to continue with the URL, or did not answer the
	/// confirmation prompt in time (see ``ConfirmationMiddleware``).
	case confirmationDenied(URL)

	/// Provides a human-readable description of the error.
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

		case let .invalidParameterValue(name, value):
			"Invalid value '\(value)' for parameter: \(name)"

		case let .routeNotFound(url):
			"No route found for URL: \(url.absoluteString)"

		case let .parsingFailed(url, underlyingErrors):
			if underlyingErrors.isEmpty {
				"Parsing failed for URL: \(url.absoluteString)"
			} else {
				"Parsing failed for URL: \(url.absoluteString); "
					+ underlyingErrors.map(\.localizedDescription).joined(separator: "; ")
			}

		case let .handlerError(message, underlyingError):
			if let underlyingError {
				"Handler error: \(message): \(underlyingError.localizedDescription)"
			} else {
				"Handler error: \(message)"
			}

		case let .missingRequiredConfiguration(component):
			"Missing required configuration: \(component)"

		case let .rateLimitExceeded(maxRequests, timeWindow):
			"Rate limit exceeded: \(maxRequests) requests in \(timeWindow) seconds"

		case let .securityViolation(reason):
			"Security violation: \(reason)"

		case let .unauthorizedAccess(url):
			"Unauthorized access to: \(url.absoluteString)"

		case let .blockedURL(url):
			"Blocked URL: \(url.absoluteString)"

		case let .confirmationDenied(url):
			"Confirmation denied for URL: \(url.absoluteString)"
		}
	}
}

// MARK: - Redaction

public extension DeepLinkError {
	/// A description safe to log, send to analytics or show to the user.
	///
	/// Same text as ``errorDescription`` with every carried URL, and every
	/// `scheme://` URL embedded in a free-form message, host or reason, passed
	/// through a default ``URLRedactor``; the value in
	/// ``invalidParameterValue(name:value:)`` always replaced; and underlying
	/// errors that are not ``DeepLinkError`` described only by their type name.
	/// Control characters are escaped (`\n`), so the description is one log line.
	var redactedDescription: String {
		redactedDescription(using: URLRedactor())
	}

	/// A description safe to log, send to analytics or show to the user.
	///
	/// - Parameter redactor: The redactor applied to URLs and parameter values.
	/// - Returns: The redacted description. See ``redactedDescription``.
	func redactedDescription(using redactor: URLRedactor) -> String {
		LogEscaping.singleLine(redactedText(using: redactor))
	}
}

private extension DeepLinkError {
	func redactedText(using redactor: URLRedactor) -> String {
		switch self {
		case let .invalidURL(url):
			Self.invalidURL(redactor.redact(url)).plainDescription

		case let .invalidParameterValue(name, _):
			Self.invalidParameterValue(name: name, value: redactor.placeholder).plainDescription

		case let .routeNotFound(url):
			Self.routeNotFound(redactor.redact(url)).plainDescription

		case let .parsingFailed(url, underlyingErrors):
			([Self.parsingFailed(url: redactor.redact(url), underlyingErrors: []).plainDescription]
				+ underlyingErrors.map { Self.redactedDescription(of: $0, using: redactor) })
				.joined(separator: "; ")

		case let .handlerError(message, underlyingError):
			([Self.handlerError(message: redactor.redactingURLs(in: message), underlyingError: nil).plainDescription]
				+ [underlyingError].compactMap(\.self).map { Self.redactedDescription(of: $0, using: redactor) })
				.joined(separator: ": ")

		case let .unauthorizedAccess(url):
			Self.unauthorizedAccess(redactor.redact(url)).plainDescription

		case let .blockedURL(url):
			Self.blockedURL(redactor.redact(url)).plainDescription

		case let .confirmationDenied(url):
			Self.confirmationDenied(redactor.redact(url)).plainDescription

		case .unsupportedScheme, .unsupportedHost, .missingRequiredParameter,
		     .missingRequiredConfiguration, .rateLimitExceeded, .securityViolation:
			redactor.redactingURLs(in: plainDescription)
		}
	}
}

private extension DeepLinkError {
	var plainDescription: String {
		errorDescription ?? ""
	}
}

extension DeepLinkError {
	static func redactedDescription(of error: any Error, using redactor: URLRedactor) -> String {
		(error as? DeepLinkError)?.redactedDescription(using: redactor) ?? String(describing: type(of: error))
	}
}

// MARK: - Equatable

extension DeepLinkError: Equatable {
	/// Structural equality for `DeepLinkError` cases.
	///
	/// Associated `any Error` payloads (`parsingFailed`, `handlerError`)
	/// cannot be compared directly — Swift's protocol existentials are
	/// not `Equatable`. Rather than reaching for `localizedDescription`
	/// (which is locale-dependent and flakes under varying runtime
	/// locales), this implementation compares the structurally-stable
	/// fields only: URL + underlying-error count for `parsingFailed`,
	/// and message + nil-ness of the underlying error for
	/// `handlerError`. Callers who need deeper comparison must unwrap
	/// the payloads and compare them themselves.
	public static func == (lhs: DeepLinkError, rhs: DeepLinkError) -> Bool {
		switch lhs {
		case let .invalidURL(l):
			if case let .invalidURL(r) = rhs {
				l == r
			} else {
				false
			}

		case let .unsupportedScheme(l):
			if case let .unsupportedScheme(r) = rhs {
				l == r
			} else {
				false
			}

		case let .unsupportedHost(l):
			if case let .unsupportedHost(r) = rhs {
				l == r
			} else {
				false
			}

		case let .missingRequiredParameter(l):
			if case let .missingRequiredParameter(r) = rhs {
				l == r
			} else {
				false
			}

		case let .invalidParameterValue(lName, lValue):
			if case let .invalidParameterValue(rName, rValue) = rhs {
				lName == rName && lValue == rValue
			} else {
				false
			}

		case let .routeNotFound(l):
			if case let .routeNotFound(r) = rhs {
				l == r
			} else {
				false
			}

		case let .parsingFailed(lURL, lErrors):
			if case let .parsingFailed(rURL, rErrors) = rhs {
				lURL == rURL && lErrors.count == rErrors.count
			} else {
				false
			}

		case let .handlerError(lMessage, lUnderlying):
			if case let .handlerError(rMessage, rUnderlying) = rhs {
				lMessage == rMessage && (lUnderlying == nil) == (rUnderlying == nil)
			} else {
				false
			}

		case let .missingRequiredConfiguration(l):
			if case let .missingRequiredConfiguration(r) = rhs {
				l == r
			} else {
				false
			}

		case let .rateLimitExceeded(lMax, lWindow):
			if case let .rateLimitExceeded(rMax, rWindow) = rhs {
				lMax == rMax && lWindow == rWindow
			} else {
				false
			}

		case let .securityViolation(l):
			if case let .securityViolation(r) = rhs {
				l == r
			} else {
				false
			}

		case let .unauthorizedAccess(l):
			if case let .unauthorizedAccess(r) = rhs {
				l == r
			} else {
				false
			}

		case let .blockedURL(l):
			if case let .blockedURL(r) = rhs {
				l == r
			} else {
				false
			}

		case let .confirmationDenied(l):
			if case let .confirmationDenied(r) = rhs {
				l == r
			} else {
				false
			}
		}
	}
}
