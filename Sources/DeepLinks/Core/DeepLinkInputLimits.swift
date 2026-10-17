//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Size limits that bound how much work an untrusted deep link can cause.
///
/// Enforce the limits as early as possible, before logging, analytics or
/// parsing touch the URL: pass them to ``SecurityMiddleware`` (placed first in
/// the chain) or to ``URLCanonicalizer``. A `nil` limit is not enforced.
/// Negative limits are clamped to `0`.
///
/// Violations throw ``DeepLinkError/securityViolation(_:)``.
///
/// ## Example
///
/// ```swift
/// builder.middleware(.security(
///     allowedSchemes: ["https", "myapp"],
///     allowedHosts: ["myapp.com"],
///     strategy: .hardened,
///     limits: .recommended
/// ))
/// ```
public struct DeepLinkInputLimits: Sendable, Equatable {
	/// The maximum length of the absolute URL string, in characters.
	public let maxURLLength: Int?

	/// The maximum number of query parameters, counting duplicates and
	/// valueless parameters (`?flag`).
	public let maxQueryParameterCount: Int?

	/// The maximum length of a single percent-decoded query parameter value, in characters.
	public let maxParameterValueLength: Int?

	/// Whether a query key that appears more than once is rejected, compared
	/// case-sensitively after percent-decoding and including valueless keys.
	/// Repeated keys let two readers see different values (parameter pollution).
	public let rejectDuplicateParameters: Bool

	/// Limits that enforce nothing; the behavior of every API before limits existed.
	public static let unlimited = DeepLinkInputLimits()

	/// Conservative limits suitable for most apps: ``DeepLinkURL/defaultMaxLength``
	/// characters, 50 query parameters, and 1024 characters per parameter value.
	public static let recommended = DeepLinkInputLimits(
		maxURLLength: DeepLinkURL.defaultMaxLength,
		maxQueryParameterCount: 50,
		maxParameterValueLength: 1024,
	)

	/// Creates input limits.
	///
	/// - Parameters:
	///   - maxURLLength: The maximum absolute URL length, or `nil` for no limit.
	///   - maxQueryParameterCount: The maximum number of query parameters, or `nil` for no limit.
	///   - maxParameterValueLength: The maximum decoded value length, or `nil` for no limit.
	///   - rejectDuplicateParameters: Whether a repeated query key is rejected. Defaults to `false`.
	public init(
		maxURLLength: Int? = nil,
		maxQueryParameterCount: Int? = nil,
		maxParameterValueLength: Int? = nil,
		rejectDuplicateParameters: Bool = false,
	) {
		self.maxURLLength = maxURLLength.map { max(0, $0) }
		self.maxQueryParameterCount = maxQueryParameterCount.map { max(0, $0) }
		self.maxParameterValueLength = maxParameterValueLength.map { max(0, $0) }
		self.rejectDuplicateParameters = rejectDuplicateParameters
	}

	/// These limits with `rejectDuplicateParameters` replaced.
	func rejectingDuplicateParameters(_ rejects: Bool) -> DeepLinkInputLimits {
		DeepLinkInputLimits(
			maxURLLength: maxURLLength,
			maxQueryParameterCount: maxQueryParameterCount,
			maxParameterValueLength: maxParameterValueLength,
			rejectDuplicateParameters: rejects,
		)
	}

	/// Checks `url` against every configured limit, cheapest first.
	///
	/// The length check runs before the query is parsed, so an oversized URL
	/// is rejected without decoding its parameters.
	///
	/// - Parameter url: The URL to check.
	/// - Throws: ``DeepLinkError/securityViolation(_:)`` describing the first limit exceeded.
	public func validate(_ url: URL) throws(DeepLinkError) {
		if let maxURLLength, url.absoluteString.count > maxURLLength {
			throw .securityViolation(SecurityViolationMessage.urlTooLong)
		}

		guard maxQueryParameterCount != nil || maxParameterValueLength != nil || rejectDuplicateParameters else { return }
		let queryItems = Self.queryItems(of: url)

		if let maxQueryParameterCount, queryItems.count > maxQueryParameterCount {
			throw .securityViolation(SecurityViolationMessage.tooManyQueryParameters)
		}

		if let maxParameterValueLength,
		   queryItems.contains(where: { ($0.value?.count ?? 0) > maxParameterValueLength })
		{
			throw .securityViolation(SecurityViolationMessage.parameterValueTooLong)
		}

		if rejectDuplicateParameters, DeepLinkURL.containsDuplicateKey(queryItems) {
			throw .securityViolation(SecurityViolationMessage.duplicateParameter)
		}
	}

	private static func queryItems(of url: URL) -> [URLQueryItem] {
		URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
			.filter { !$0.name.isEmpty || $0.value != nil } ?? []
	}
}
