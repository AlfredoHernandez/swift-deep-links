//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("DeepLinkCoordinator Tests")
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
        middlewareCoordinator.add(StoppingMiddleware())

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
        let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
        let delegate = DelegateSpy()
        coordinator.delegate = delegate
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
        let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
        let delegate = DelegateSpy()
        coordinator.delegate = delegate
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
        let coordinator = DeepLinkCoordinator(routing: routingStub, handler: handlerSpy)
        let delegate = DelegateSpy()
        coordinator.delegate = delegate
        let url = try #require(URL(string: "test://delegate"))
        routingStub.shouldThrowError = true

        _ = await coordinator.handle(url: url)

        #expect(delegate.didFailCalls.count == 1)
        #expect(delegate.didFailCalls.first?.url == url)
        #expect(delegate.didFailCalls.first?.error is TestError)
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

    // MARK: - Test doubles

    enum TestRoute: DeepLinkRoute, Equatable {
        case route1
        case route2
        case route3

        var id: String {
            switch self {
            case .route1: "route1"

            case .route2: "route2"

            case .route3: "route3"
            }
        }
    }

    final class DeepLinkRoutingStub<Route: DeepLinkRoute>: DeepLinkRouting {
        var routesToReturn: [Route] = []
        var shouldThrowError = false

        func route(from _: URL) async throws -> [Route] {
            if shouldThrowError {
                throw TestError.routingError
            }

            return routesToReturn
        }
    }

    final class DeepLinkHandlerSpy<Route: DeepLinkRoute & Equatable>: DeepLinkHandler {
        private(set) var handledRoutes: [Route] = []
        var shouldThrowError = false
        var errorRoute: Route?

        func handle(_ route: Route) async throws {
            if shouldThrowError, errorRoute == route {
                throw TestError.handlerError
            }

            handledRoutes.append(route)
        }
    }

    enum TestError: Error {
        case routingError
        case handlerError
    }

    /// Middleware that always returns nil to stop processing
    final class StoppingMiddleware: DeepLinkMiddleware, @unchecked Sendable {
        func intercept(_: URL) async throws -> URL? {
            nil // Always stops processing
        }
    }

    /// Test delegate that tracks all delegate method calls
    final class DelegateSpy: DeepLinkCoordinatorDelegate {
        private(set) var willProcessCalls: [URL] = []
        private(set) var didProcessCalls: [(url: URL, result: DeepLinkResultProtocol)] = []
        private(set) var didFailCalls: [(url: URL, error: Error)] = []

        func coordinator(_: AnyObject, willProcess url: URL) {
            willProcessCalls.append(url)
        }

        func coordinator(_: AnyObject, didProcess url: URL, result: DeepLinkResultProtocol) {
            didProcessCalls.append((url: url, result: result))
        }

        func coordinator(_: AnyObject, didFailProcessing url: URL, error: Error) {
            didFailCalls.append((url: url, error: error))
        }
    }
}
