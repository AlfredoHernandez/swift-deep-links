//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct ReadinessMiddlewareCoordinatorIntegrationTests {
	private let firstURL = URL(string: "myapp://first")!
	private let secondURL = URL(string: "myapp://second")!

	@Test
	func `coordinator.handle returns a middleware-stopped result while the queue is not ready`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: ImmediateRouting<TestRoute>(routes: [.route1]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		let result = await coordinator.handle(url: firstURL)

		#expect(result.wasStoppedByMiddleware)
		#expect(result.routes.isEmpty)
		#expect(result.successfulRoutes == 0)
		#expect(handler.handledRoutes.isEmpty)
		#expect(queue.pendingURLs == [firstURL])
	}

	@Test
	func `coordinator.handle routes normally once the queue is marked ready directly`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: ImmediateRouting<TestRoute>(routes: [.route1]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		_ = queue.markReady()

		let result = await coordinator.handle(url: firstURL)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1])
		#expect(handler.handledRoutes == [.route1])
		#expect(queue.pendingCount == 0)
	}

	@Test
	func `URLs queued while not ready are executed after markReadyAndDrain`() async {
		let queue = DeepLinkReadinessQueue()
		let handler = CollectingHandler<TestRoute>()
		let coordinator = DeepLinkCoordinator(
			routing: ImmediateRouting<TestRoute>(routes: [.route1]),
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [ReadinessMiddleware(queue: queue)]),
		)

		let stoppedFirst = await coordinator.handle(url: firstURL)
		let stoppedSecond = await coordinator.handle(url: secondURL)

		#expect(stoppedFirst.wasStoppedByMiddleware)
		#expect(stoppedSecond.wasStoppedByMiddleware)
		#expect(handler.handledRoutes.isEmpty)

		let drained = await coordinator.markReadyAndDrain(queue: queue)

		#expect(drained.count == 2)
		#expect(drained.map(\.wasSuccessful) == [true, true])
		#expect(handler.handledRoutes == [.route1, .route1])
	}
}
