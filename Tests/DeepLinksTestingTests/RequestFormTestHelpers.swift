//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import Foundation

extension DeepLinkMiddleware {
	/// Runs the request form on `url` with an unknown context and returns the resulting URL.
	func intercept(url: URL) async throws -> URL? {
		try await intercept(DeepLinkRequest(url: url))?.url
	}
}
