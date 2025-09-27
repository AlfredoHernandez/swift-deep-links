//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Protocol for URL transformers
public protocol URLTransformer: Sendable {
    func transform(_ url: URL) async throws -> URL
}

/// Default URL transformer that normalizes URLs
public final class URLNormalizationTransformer: URLTransformer {
    public init() {}

    public func transform(_ url: URL) async throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DeepLinkError.invalidURL(url)
        }

        // Normalize path
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !components.path.isEmpty, !components.path.hasPrefix("/") {
            components.path = "/" + components.path
        }

        // Remove empty query parameters
        components.queryItems = components.queryItems?.filter { $0.value != nil && !$0.value!.isEmpty }

        guard let normalizedURL = components.url else {
            throw DeepLinkError.invalidURL(url)
        }

        return normalizedURL
    }
}
