//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import Foundation

public extension DeepLinkCoordinator {
	/// Marks the supplied readiness queue as ready and drains every URL that
	/// was queued while it was gating traffic.
	///
	/// Each drained URL resumes the middleware chain right after the
	/// ``ReadinessMiddleware`` that queued it: middleware placed before the
	/// readiness gate is not run a second time, while middleware placed after
	/// it (authentication, security, rate limiting, transforms) evaluates the
	/// link at drain time, so app state that changed while the link waited —
	/// such as a sign-out — is honored. If `queue` is not registered through a
	/// ``ReadinessMiddleware``, every drained URL runs through the whole chain.
	///
	/// Delegate notifications (``DeepLinkCoordinatorDelegate/coordinator(_:willProcess:)``,
	/// ``DeepLinkCoordinatorDelegate/coordinator(_:didProcess:result:)``,
	/// ``DeepLinkCoordinatorDelegate/coordinator(_:didFailProcessing:error:)``)
	/// continue to fire for each drained URL so observers keep receiving
	/// lifecycle events.
	///
	/// ## Example
	///
	/// ```swift
	/// let queue = DeepLinkReadinessQueue()
	/// let coordinator = try DeepLinkCoordinatorBuilder<AppRoute>()
	///     .parser(MyParser())
	///     .handler(appHandler)
	///     .middleware(.readiness(queue: queue), .analytics(provider: provider))
	///     .build()
	///
	/// // ...once the app is ready to service deep links:
	/// let drained = await coordinator.markReadyAndDrain(queue: queue)
	/// print("drained \(drained.count) queued deep links")
	/// ```
	///
	/// - Parameter queue: The readiness queue to mark ready and drain.
	/// - Returns: One ``DeepLinkResult`` per drained URL, in queue order.
	@discardableResult
	func markReadyAndDrain(queue: any ReadinessQueue) async -> [DeepLinkResult<Route>] {
		let pending = queue.markReadyReturningRequests()
		var results: [DeepLinkResult<Route>] = []
		results.reserveCapacity(pending.count)
		for request in pending {
			await results.append(handleResumingAfterReadiness(request, of: queue))
		}
		return results
	}
}
