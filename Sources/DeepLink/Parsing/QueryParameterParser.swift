//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

/// A protocol that defines how to parse query parameters into strongly-typed objects.
///
/// The `QueryParameterParser` protocol provides a standardized way to convert
/// URL query parameters (represented as a dictionary of strings) into strongly-typed
/// objects. This enables type-safe parameter handling in deep link parsers.
///
/// ## Implementation
///
/// The library provides `JSONQueryParameterParser` as a default implementation
/// that uses JSON encoding/decoding. You can also implement this protocol directly
/// for custom parameter parsing logic:
///
/// ```swift
/// final class CustomParameterParser: QueryParameterParser {
///     func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T {
///         // Custom parsing logic
///         let data = try customParsingMethod(parameters)
///         return try JSONDecoder().decode(type, from: data)
///     }
/// }
/// ```
///
/// ## Usage in Parsers
///
/// Query parameter parsers are typically used within `DeepLinkParser` implementations:
///
/// ```swift
/// final class UserParser: DeepLinkParser {
///     private let parameterParser: any QueryParameterParser
///
///     func parse(from url: URL) throws -> [UserRoute] {
///         let deepLinkURL = try DeepLinkURL(url: url)
///         let params = try parameterParser.parse(UserParameters.self, from: deepLinkURL.queryParameters)
///         return [.profile(userId: params.userId)]
///     }
/// }
/// ```
public protocol QueryParameterParser {
	/// Parses query parameters into a strongly-typed object.
	///
	/// This method should convert the string-based query parameter dictionary
	/// into a strongly-typed object of the specified type.
	///
	/// - Parameters:
	///   - type: The type to parse the parameters into
	///   - parameters: The query parameters as a dictionary of strings
	/// - Returns: An instance of the specified type with the parsed parameters
	/// - Throws: Parsing errors if the conversion fails
	func parse<T: Decodable>(_ type: T.Type, from parameters: [String: String]) throws -> T
}
