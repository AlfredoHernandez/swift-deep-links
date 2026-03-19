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
			logger.error("Error while parsing data from deep link for data \(type) with error: \(error)")
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
	/// - Parameters:
	///   - type: The type to decode the parameters into
	///   - parameters: The query parameters with array support
	/// - Returns: An instance of the specified type with the parsed parameters
	/// - Throws: JSON encoding/decoding errors if the conversion fails
	public func parse<T: Decodable>(_ type: T.Type, fromAll parameters: [String: [String]]) throws -> T {
		do {
			// Convert [String: [String]] to a format suitable for JSON decoding
			// If an array has only one element, unwrap it to a single value
			// This allows both single values and arrays to be decoded properly
			var normalizedParams: [String: Any] = [:]
			for (key, values) in parameters {
				if values.count == 1 {
					normalizedParams[key] = values[0]
				} else {
					normalizedParams[key] = values
				}
			}

			let jsonData = try JSONSerialization.data(withJSONObject: normalizedParams)
			return try jsonDecoder.decode(type, from: jsonData)
		} catch {
			logger.error("Error while parsing array data from deep link for data \(type) with error: \(error)")
			throw error
		}
	}
}
