//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("DeepLinkCoordinator Tests")
@MainActor
struct DeepLinkCoordinatorTests {
	@Test("DeepLinkCoordinator handle processes single route successfully")
	func deepLinkCoordinator_handle_processesSingleRouteSuccessfully() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://route1"))

		routingStub.routesToReturn = [.route1]

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1])
		#expect(result.successfulRoutes == 1)
		#expect(result.failedRoutes == 0)
		#expect(result.errors.isEmpty)
		#expect(result.originalURL == url)
		#expect(result.processedURL == url)
		#expect(handlerSpy.handledRoutes == [.route1])
	}

	@Test("DeepLinkCoordinator handle processes multiple routes successfully")
	func deepLinkCoordinator_handle_processesMultipleRoutesSuccessfully() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://multiple"))

		routingStub.routesToReturn = [.route1, .route2, .route3]

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1, .route2, .route3])
		#expect(result.successfulRoutes == 3)
		#expect(result.failedRoutes == 0)
		#expect(result.errors.isEmpty)
		#expect(handlerSpy.handledRoutes == [.route1, .route2, .route3])
	}

	@Test("DeepLinkCoordinator handle processes empty routes array")
	func deepLinkCoordinator_handle_processesEmptyRoutesArray() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://empty"))

		routingStub.routesToReturn = []

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes.isEmpty)
		#expect(result.successfulRoutes == 0)
		#expect(result.failedRoutes == 0)
		#expect(result.errors.isEmpty)
		#expect(handlerSpy.handledRoutes.isEmpty)
	}

	@Test("DeepLinkCoordinator handle continues processing after handler error")
	func deepLinkCoordinator_handle_continuesProcessingAfterHandlerError() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://error"))

		routingStub.routesToReturn = [.route1, .route2, .route3]
		handlerSpy.shouldThrowError = true
		handlerSpy.errorRoute = .route2

		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(result.routes == [.route1, .route2, .route3])
		#expect(result.successfulRoutes == 2)
		#expect(result.failedRoutes == 1)
		#expect(result.errors.count == 1)
		#expect(handlerSpy.handledRoutes == [.route1, .route3]) // route2 failed, so it's not in handledRoutes
	}

	@Test("DeepLinkCoordinator handle handles routing error gracefully")
	func deepLinkCoordinator_handle_handlesRoutingErrorGracefully() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://routing-error"))
		routingStub.shouldThrowError = true

		let result = await coordinator.handle(url: url)

		#expect(!result.wasSuccessful)
		#expect(result.routes.isEmpty)
		#expect(result.successfulRoutes == 0)
		#expect(result.failedRoutes == 0)
		#expect(result.errors.count == 1)
		#expect(handlerSpy.handledRoutes.isEmpty)
	}

	@Test("DeepLinkCoordinator handle processes routes with delay between executions")
	func deepLinkCoordinator_handle_processesRoutesWithDelayBetweenExecutions() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://delay"))
		routingStub.routesToReturn = [.route1, .route2]

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1, .route2])
		#expect(result.successfulRoutes == 2)
		#expect(result.executionTime >= 0.5) // Should have at least 500ms delay
		#expect(handlerSpy.handledRoutes == [.route1, .route2])
	}

	@Test("DeepLinkCoordinator handle returns result when middleware stops processing")
	func deepLinkCoordinator_handle_returnsResultWhenMiddlewareStopsProcessing() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let middlewareCoordinator = DeepLinkMiddlewareCoordinator()
		let coordinator = DeepLinkCoordinator(
			routing: routingStub,
			handler: handlerSpy,
			middlewareCoordinator: middlewareCoordinator,
		)
		let url = try #require(URL(string: "test://middleware-stop"))

		// Add middleware that returns nil (stops processing)
		await middlewareCoordinator.add(StoppingMiddleware())

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful) // Should be successful even when stopped by middleware
		#expect(result.wasStoppedByMiddleware)
		#expect(result.processedURL == nil)
		#expect(result.routes.isEmpty)
		#expect(result.successfulRoutes == 0)
		#expect(result.failedRoutes == 0)
		#expect(result.errors.isEmpty)
		#expect(handlerSpy.handledRoutes.isEmpty)
	}

	@Test("DeepLinkCoordinator notifies delegate when processing starts")
	func deepLinkCoordinator_notifiesDelegateWhenProcessingStarts() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegate = CoordinatorDelegateSpy()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy, delegate: delegate)
		let url = try #require(URL(string: "test://delegate"))

		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(delegate.willProcessCalls.count == 1)
		#expect(delegate.willProcessCalls.first == url)
	}

	@Test("DeepLinkCoordinator notifies delegate when processing completes successfully")
	func deepLinkCoordinator_notifiesDelegateWhenProcessingCompletesSuccessfully() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegate = CoordinatorDelegateSpy()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy, delegate: delegate)
		let url = try #require(URL(string: "test://delegate"))

		routingStub.routesToReturn = [.route1]

		_ = await coordinator.handle(url: url)

		#expect(delegate.didProcessCalls.count == 1)
		#expect(delegate.didProcessCalls.first?.url == url)
		#expect(delegate.didProcessCalls.first?.result.wasSuccessful == true)
	}

	@Test("DeepLinkCoordinator notifies delegate when processing fails")
	func deepLinkCoordinator_notifiesDelegateWhenProcessingFails() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let delegate = CoordinatorDelegateSpy()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy, delegate: delegate)
		let url = try #require(URL(string: "test://delegate"))
		routingStub.shouldThrowError = true

		_ = await coordinator.handle(url: url)

		#expect(delegate.didFailCalls.count == 1)
		#expect(delegate.didFailCalls.first?.url == url)
		#expect(delegate.didFailCalls.first?.error is DeepLinkError)
	}

	@Test("DeepLinkCoordinator works without delegate")
	func deepLinkCoordinator_worksWithoutDelegate() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()
		let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
		let url = try #require(URL(string: "test://no-delegate"))

		routingStub.routesToReturn = [.route1]

		let result = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1])
		#expect(handlerSpy.handledRoutes == [.route1])
	}

	@Test("CoordinatorOf type alias works correctly")
	func coordinatorOf_typeAlias_worksCorrectly() async throws {
		let routingStub = DeepLinkRoutingStub<TestRoute>()
		let handlerSpy = DeepLinkHandlerSpy<TestRoute>()

		// Using the convenience type alias
		let coordinator: CoordinatorOf<TestRoute> = DeepLinkCoordinator(
			routing: routingStub,
			handler: handlerSpy,
		)

		let url = try #require(URL(string: "test://type-alias"))
		routingStub.routesToReturn = [.route1, .route2]

		let result: ResultOf<TestRoute> = await coordinator.handle(url: url)

		#expect(result.wasSuccessful)
		#expect(result.routes == [.route1, .route2])
		#expect(result.successfulRoutes == 2)
		#expect(handlerSpy.handledRoutes == [.route1, .route2])
	}

	// MARK: - Test doubles

	/// Middleware that always returns nil to stop processing
	final class StoppingMiddleware: DeepLinkMiddleware {
		func intercept(_: URL) async throws -> URL? {
			nil
		}
	}
}
