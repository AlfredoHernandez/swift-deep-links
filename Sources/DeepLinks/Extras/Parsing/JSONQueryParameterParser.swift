//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation
import OSLog

/// A query parameter parser that uses JSON encoding/decoding for parameter conversion.
///
/// `JSONQueryParameterParser` provides a convenient way to parse query parameters
/// into strongly-typed objects using Swift's `Codable` protocol. It converts the
/// query parameter dictionary to JSON and then decodes it into the target type.
///
/// ## Usage
///
/// ```swift
/// struct UserParameters: Decodable {
///     let userId: String
///     let name: String
///     let isActive: Bool
/// }
///
/// let parser = JSONQueryParameterParser()
/// let params = try parser.parse(UserParameters.self, from: queryParameters)
/// ```
///
/// ## Limitations
///
/// This parser has some limitations:
/// - All parameter values must be valid JSON strings
/// - Complex nested structures may not work well with URL query parameters
/// - Boolean and numeric values are parsed as strings first, then converted
///
/// For more complex parameter structures, consider implementing a custom parser.
public final class JSONQueryParameterParser: QueryParameterParser {
	private let logger = Logger(subsystem: "swift-deep-links", category: "JSONQueryParameterParser")
	private let jsonDecoder: JSONDecoder

	/// Creates a new JSON query parameter parser.
	///
	/// - Parameter jsonDecoder: The JSON decoder to use for parsing. Defaults to a standard `JSONDecoder`
	public init(jsonDecoder: JSONDecoder = JSONDecoder()) {
		self.jsonDecoder = jsonDecoder
	}

	/// Parses query parameters into a strongly-typed object using JSON decoding.
	///
	/// This method converts the parameter dictionary to JSON data and then decodes
	/// it into the specified type using the configured JSON decoder.
	///
	/// - Parameters:
	///   - type: The type to decode the parameters into
	///   - parameters: The query parameters as a dictionary
	/// - Returns: An instance of the specified type with the parsed parameters
	/// - Throws: JSON encoding/decoding errors if the conversion fails
	public func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T {
		do {
			let jsonData = try JSONSerialization.data(withJSONObject: parameters)
			return try jsonDecoder.decode(type, from: jsonData)
		} catch {
			logger.error("Error while parsing data from deep link for data \(type) with error: \(DeepLinkLogPrivacy.redacted.describe(error))")
			throw error
		}
	}

	/// Parses query parameters (including arrays) into a strongly-typed object using JSON decoding.
	///
	/// This method supports array parameters where the same key appears multiple times:
	/// `myapp://products?tags=electronics&tags=new&tags=sale`
	///
	/// ## Usage Example
	///
	/// ```swift
	/// struct ProductParameters: Decodable {
	///     let tags: [String]
	///     let category: String
	/// }
	///
	/// let parser = JSONQueryParameterParser()
	/// let params = try parser.parse(ProductParameters.self, fromAll: deepLinkURL.allQueryParameters)
	/// // params.tags = ["electronics", "new", "sale"]
	/// ```
	///
	/// ## Single-value vs array keys
	///
	/// To accommodate both scalar and array-typed model fields, this method performs
	/// up to two decode passes:
	///
	/// 1. First pass unwraps single-element values (`?tags=foo` → `"foo"`), matching
	///    the common case where most URLs pass a single value and models declare
	///    scalar fields (`let tags: String`).
	/// 2. If the first pass fails to decode, a second pass keeps every value as an
	///    array (`?tags=foo` → `["foo"]`). This lets models that declare
	///    `let tags: [String]` decode a URL where the key only appears once.
	///
	/// If both passes fail, the **first** pass's decoding error is rethrown — it
	/// corresponds to the scalar-oriented shape that most models target, so its
	/// diagnostic is typically closer to the real problem (missing required key,
	/// wrong type) than the array-shape error surfaced by the fallback.
	///
	/// - Parameters:
	///   - type: The type to decode the parameters into
	///   - parameters: The query parameters with array support
	/// - Returns: An instance of the specified type with the parsed parameters
	/// - Throws: JSON encoding/decoding errors if the conversion fails
	public func parse<T: Decodable>(_ type: T.Type, fromAll parameters: [String: [String]]) throws -> T {
		do {
			return try decode(type, from: normalized(parameters, unwrapSingles: true))
		} catch let firstError {
			do {
				return try decode(type, from: normalized(parameters, unwrapSingles: false))
			} catch {
				logger.error("Error while parsing array data from deep link for data \(type) with error: \(DeepLinkLogPrivacy.redacted.describe(firstError))")
				throw firstError
			}
		}
	}

	private func decode<T: Decodable>(_ type: T.Type, from normalizedParams: [String: Any]) throws -> T {
		let jsonData = try JSONSerialization.data(withJSONObject: normalizedParams)
		return try jsonDecoder.decode(type, from: jsonData)
	}

	private func normalized(_ parameters: [String: [String]], unwrapSingles: Bool) -> [String: Any] {
		var result: [String: Any] = [:]
		for (key, values) in parameters {
			if unwrapSingles, values.count == 1 {
				result[key] = values[0]
			} else {
				result[key] = values
			}
		}
		return result
	}
}
