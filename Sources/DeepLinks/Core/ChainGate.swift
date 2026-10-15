//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import Foundation

/// Middleware that holds links back in a ``ReadinessQueue`` until the app is
/// ready, so the coordinator can defer settlement at it and resume the chain
/// after it when the queue drains.
protocol ChainGate: DeepLinkMiddleware {
	/// Whether this gate holds links in `queue`.
	func isGating(_ queue: any ReadinessQueue) -> Bool
}
