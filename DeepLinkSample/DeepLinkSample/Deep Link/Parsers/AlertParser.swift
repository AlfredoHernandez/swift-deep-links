//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

/// A parser that handles alert deep link URLs and converts them to `AppRoute` instances.
///
/// This parser is responsible for:
/// - Parsing URLs with the "alert" host
/// - Extracting alert parameters (title, message, type)
/// - Converting parsed data to `AppRoute.alert` instances
/// - Handling alert type validation and fallbacks
///
/// ## Supported URL Format:
/// ```
/// deeplink://alert?title=<title>&message=<message>&type=<type>
/// ```
///
/// ## Parameters:
/// - `title`: The alert title (required)
/// - `message`: The alert message content (required)
/// - `type`: The alert type - info, warning, error, or success (optional, defaults to info)
///
/// ## Error Handling:
/// - Throws `DeepLinkError.unsupportedHost` for non-alert URLs
/// - Uses default alert type (.info) if the provided type is invalid
final class AlertParser: DeepLinkParser {
	typealias Route = AppRoute
	private let parameterParser: any QueryParameterParser

	/// Initializes the alert parser with a query parameter parser.
	///
	/// - Parameter parameterParser: The parser used to extract query parameters from URLs
	init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
		self.parameterParser = parameterParser
	}

	/// Parses alert deep link URLs (deeplink://alert) into AppRoute instances.
	///
	/// - Parameter url: The deep link URL to parse
	/// - Returns: An array containing the parsed alert route
	/// - Throws: `DeepLinkError.unsupportedHost` if the URL host is not "alert"
	func parse(from url: URL) throws -> [AppRoute] {
		let deepLinkURL = try DeepLinkURL(url: url)

		switch deepLinkURL.host {
		case "alert":
			return try parseAlertData(from: deepLinkURL)

		default:
			throw DeepLinkError.unsupportedHost(deepLinkURL.host)
		}
	}

	/// Extracts alert parameters and creates AppRoute.alert instance.
	private func parseAlertData(from url: DeepLinkURL) throws -> [AppRoute] {
		let data = try parameterParser.parse(AlertDeepLinkParameters.self, from: url.queryParameters)
		let alertType = Alert.AlertType(rawValue: data.type) ?? .info
		return [.alert(.alert(title: data.title, message: data.message, type: alertType))]
	}
}
