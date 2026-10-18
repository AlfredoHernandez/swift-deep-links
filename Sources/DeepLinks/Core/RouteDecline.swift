//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation
import os

/// The error a route guard declined the route with, if any.
final class RouteDecline: Sendable {
	private let declinedError = OSAllocatedUnfairLock<DeepLinkError?>(initialState: nil)

	func markDeclined(with error: DeepLinkError) {
		declinedError.withLock { $0 = error }
	}

	/// Whether the route failed with the decline itself, so nothing ran; a
	/// wrapper that caught the decline and failed differently may have acted.
	func declined(_ error: any Error) -> Bool {
		guard let thrown = error as? DeepLinkError else { return false }
		return declinedError.withLock { $0 == thrown }
	}
}
