//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLink
import Foundation

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
