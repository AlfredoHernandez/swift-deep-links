//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

/// Parser for profile-related deep links.
///
/// This parser demonstrates the use of the `ParserOf<Route>` type alias
/// for cleaner type signatures when conforming to `DeepLinkParser`.
///
/// ## Example URLs:
/// ```
/// deeplink://profile?userID=123&name=John
/// ```
final class ProfileParser: DeepLinkParser {
	typealias Route = AppRoute
	private let parameterParser: any QueryParameterParser

	init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
		self.parameterParser = parameterParser
	}

	func parse(from url: URL) throws -> [AppRoute] {
		let deepLinkURL = try DeepLinkURL(url: url)

		switch deepLinkURL.host {
		case "profile":
			return try parseProfileData(from: deepLinkURL)

		default:
			throw DeepLinkError.unsupportedHost(deepLinkURL.host)
		}
	}

	private func parseProfileData(from url: DeepLinkURL) throws -> [AppRoute] {
		let data = try parameterParser.parse(ProfileDeepLinkParameters.self, from: url.queryParameters)
		return [.sheet(.profile(userID: data.userID, name: data.name))]
	}
}
