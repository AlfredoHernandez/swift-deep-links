//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
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
    private let logger = Logger(subsystem: "swift-deep-link", category: "JSONQueryParameterParser")
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
}
