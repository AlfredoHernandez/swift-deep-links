//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

final class SettingsParser: DeepLinkParser {
    typealias Route = AppRoute
    private let parameterParser: any QueryParameterParser

    init(parameterParser: any QueryParameterParser = JSONQueryParameterParser()) {
        self.parameterParser = parameterParser
    }

    func parse(from url: URL) throws -> [AppRoute] {
        let deepLinkURL = try DeepLinkURL(url: url)

        switch deepLinkURL.host {
        case "settings":
            return try parseSettingsData(from: deepLinkURL)

        default:
            throw DeepLinkError.unsupportedHost(deepLinkURL.host)
        }
    }

    private func parseSettingsData(from url: DeepLinkURL) throws -> [AppRoute] {
        let data = try parameterParser.parse(SettingsDeepLinkParameters.self, from: url.queryParameters)
        return [.stack(.settings(section: data.section))]
    }
}
