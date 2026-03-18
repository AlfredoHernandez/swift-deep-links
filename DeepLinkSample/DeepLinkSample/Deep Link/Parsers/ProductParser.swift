//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

final class ProductParser: DeepLinkParser {
	typealias Route = AppRoute
	private let parameterParser: any QueryParameterParser

	init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
		self.parameterParser = parameterParser
	}

	func parse(from url: URL) throws -> [AppRoute] {
		let deepLinkURL = try DeepLinkURL(url: url)

		switch deepLinkURL.host {
		case "product":
			return try parseProductData(from: deepLinkURL)

		default:
			throw DeepLinkError.unsupportedHost(deepLinkURL.host)
		}
	}

	private func parseProductData(from url: DeepLinkURL) throws -> [AppRoute] {
		let data = try parameterParser.parse(ProductDeepLinkParameters.self, from: url.queryParameters)
		return [.stack(.product(productID: data.productID, category: data.category))]
	}
}
