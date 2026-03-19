//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

final class InformationParser: DeepLinkParser {
	typealias Route = AppRoute
	private let parameterParser: any QueryParameterParser

	init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
		self.parameterParser = parameterParser
	}

	func parse(from url: URL) throws -> [AppRoute] {
		let deepLinkURL = try DeepLinkURL(url: url)

		switch deepLinkURL.host {
		case "info":
			return try parseInfoData(from: deepLinkURL)

		default:
			throw DeepLinkError.unsupportedHost(deepLinkURL.host)
		}
	}

	private func parseInfoData(from url: DeepLinkURL) throws -> [AppRoute] {
		let data = try parameterParser.parse(InfoDeepLinkParameters.self, from: url.queryParameters)
		return [.sheet(.info(title: data.brief, brief: data.title))]
	}
}
