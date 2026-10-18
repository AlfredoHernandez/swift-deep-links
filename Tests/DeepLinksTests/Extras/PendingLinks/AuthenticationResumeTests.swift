//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct AuthenticationResumeTests {
	/// These tests resume links handled as `.unknown`, which the default pending sources skip.
	private static let everySource = Set(DeepLinkContext.Source.allCases)
	private let protectedURL = URL(string: "myapp://account/settings")!
	private let publicURL = URL(string: "myapp://home")!

	// MARK: - Middleware

	@Test
	func `unauthenticated protected link is stored and still rejected`() async {
		let store = InMemoryPendingLinkStore()
		let sut = makeMiddleware(isAuthenticated: false, store: store)

		await #expect(throws: DeepLinkError.unauthorizedAccess(protectedURL)) {
			try await sut.intercept(url: protectedURL)
		}
		#expect(await store.takeAll() == [protectedURL])
	}

	@Test
	func `authenticated protected link is not stored`() async throws {
		let store = InMemoryPendingLinkStore()
		let sut = makeMiddleware(isAuthenticated: true, store: store)

		_ = try await sut.intercept(url: protectedURL)

		#expect(await store.takeAll() == [])
	}

	@Test
	func `unprotected link is not stored`() async throws {
		let store = InMemoryPendingLinkStore()
		let sut = makeMiddleware(isAuthenticated: false, store: store)

		_ = try await sut.intercept(url: publicURL)

		#expect(await store.takeAll() == [])
	}

	@Test
	func `factory wires the pending link store`() async {
		let store = InMemoryPendingLinkStore()
		let sut: AuthenticationMiddleware = .authentication(
			provider: SwitchableAuthenticationProvider(isAuthenticated: false),
			protectedHosts: ["account"],
			pendingLinks: store,
			pendingSources: Self.everySource,
		)

		_ = try? await sut.intercept(url: protectedURL)

		#expect(await store.takeAll() == [protectedURL])
	}

	// MARK: - Coordinator Resume

	@Test
	func `resume after login handles the stored link and empties the store`() async {
		let (coordinator, auth, store, handler) = makeCoordinator()
		await coordinator.handle(url: protectedURL)

		auth.isLoggedIn = true
		let results = await coordinator.resumePendingLinks(from: store)

		#expect(results.map(\.wasSuccessful) == [true])
		#expect(results.map(\.originalURL) == [protectedURL])
		#expect(handler.handledRoutes == [.route1])
		#expect(await store.takeAll() == [])
	}

	@Test
	func `resume while still logged out rejects again and keeps the link pending`() async {
		let (coordinator, _, store, handler) = makeCoordinator()
		await coordinator.handle(url: protectedURL)

		let results = await coordinator.resumePendingLinks(from: store)

		#expect(results.first?.firstDeepLinkError == .unauthorizedAccess(protectedURL))
		#expect(handler.handledRoutes.isEmpty)
		#expect(await store.takeAll() == [protectedURL])
	}

	@Test
	func `resume runs the whole middleware chain again`() async {
		let counter = InterceptCounter()
		let (coordinator, auth, store, _) = makeCoordinator(leading: [counter])
		await coordinator.handle(url: protectedURL)

		auth.isLoggedIn = true
		await coordinator.resumePendingLinks(from: store)

		#expect(counter.count == 2)
	}

	@Test
	func `replay protection placed after authentication does not drop a link resumed inside its window`() async {
		let clock = ManualDateProvider()
		let auth = SwitchableAuthenticationProvider(isAuthenticated: false)
		let store = InMemoryPendingLinkStore(dateProvider: clock.dateProvider)
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: DeepLinkHandlerSpy<TestRoute>(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				AuthenticationMiddleware(authProvider: auth, protectedHosts: ["account"], pendingLinks: store, pendingSources: Self.everySource),
				ReplayProtectionMiddleware(window: 2, dateProvider: clock.dateProvider),
			]),
		)
		await coordinator.handle(url: protectedURL)

		clock.advance(by: 1)
		auth.isLoggedIn = true

		#expect(await coordinator.resumePendingLinks(from: store).map(\.wasSuccessful) == [true])
	}

	@Test
	func `resume with an empty store returns no results`() async {
		let (coordinator, _, store, _) = makeCoordinator()

		#expect(await coordinator.resumePendingLinks(from: store).isEmpty)
	}

	// MARK: - Helpers

	private func makeMiddleware(isAuthenticated: Bool, store: any PendingLinkStore) -> AuthenticationMiddleware {
		AuthenticationMiddleware(
			authProvider: SwitchableAuthenticationProvider(isAuthenticated: isAuthenticated),
			protectedHosts: ["account"],
			pendingLinks: store,
			pendingSources: Self.everySource,
		)
	}

	private func makeCoordinator(
		leading: [any DeepLinkMiddleware] = [],
	) -> (DeepLinkCoordinator<TestRoute>, SwitchableAuthenticationProvider, InMemoryPendingLinkStore, DeepLinkHandlerSpy<TestRoute>) {
		let auth = SwitchableAuthenticationProvider(isAuthenticated: false)
		let store = InMemoryPendingLinkStore()
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.routesToReturn = [.route1]
		let handler = DeepLinkHandlerSpy<TestRoute>()
		let middleware = leading + [
			AuthenticationMiddleware(authProvider: auth, protectedHosts: ["account"], pendingLinks: store, pendingSources: Self.everySource),
		]
		let coordinator = DeepLinkCoordinator(
			routing: routing,
			handler: handler,
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: middleware),
		)
		return (coordinator, auth, store, handler)
	}
}

// MARK: - Test Doubles

private final class SwitchableAuthenticationProvider: AuthenticationProvider {
	private let state: OSAllocatedUnfairLock<Bool>

	init(isAuthenticated: Bool) {
		state = OSAllocatedUnfairLock(initialState: isAuthenticated)
	}

	var isLoggedIn: Bool {
		get { state.withLock { $0 } }
		set { state.withLock { $0 = newValue } }
	}

	func isAuthenticated() -> Bool {
		isLoggedIn
	}
}

private final class InterceptCounter: DeepLinkMiddleware {
	private let state = OSAllocatedUnfairLock(initialState: 0)

	var count: Int {
		state.withLock { $0 }
	}

	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		state.withLock { $0 += 1 }
		return request
	}
}
