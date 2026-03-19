//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// A protocol that defines how to parse URLs into specific deep link routes.
///
/// The `DeepLinkParser` protocol is responsible for converting raw URLs into
/// structured route objects that can be handled by the application. Each parser
/// should be designed to handle specific URL patterns or schemes.
///
/// ## Implementation
///
/// Implement this protocol to define how URLs are parsed into your specific route types:
///
/// ```swift
/// final class UserDeepLinkParser: DeepLinkParser {
///     typealias Route = UserRoute
///
///     func parse(from url: URL) throws -> [UserRoute] {
///         let deepLinkURL = try DeepLinkURL(url: url)
///
///         switch deepLinkURL.host {
///         case "profile":
///             guard let userID = deepLinkURL.queryParameters["userId"] else {
///                 throw DeepLinkError.missingRequiredParameter("userId")
///             }
///             return [.profile(userId: userId)]
///         default:
///             throw DeepLinkError.unsupportedHost(deepLinkURL.host)
///         }
///     }
/// }
/// ```
///
/// ## Multiple Routes
///
/// A single parser can return multiple routes from a single URL, allowing for
/// complex navigation scenarios where one deep link should trigger multiple actions.
///
/// - AssociatedType Route: The type of route this parser can produce
public protocol DeepLinkParser<Route>: Sendable {
	/// The type of route this parser can produce.
	associatedtype Route: DeepLinkRoute

	/// Parses a URL into one or more deep link routes.
	///
	/// This method should analyze the URL structure and extract the necessary
	/// information to create appropriate route objects. It should throw appropriate
	/// errors for invalid or unsupported URLs.
	///
	/// - Parameter url: The URL to parse
	/// - Returns: An array of routes that correspond to the URL
	/// - Throws: `DeepLinkError` or other parsing-related errors
	func parse(from url: URL) async throws -> [Route]
}
