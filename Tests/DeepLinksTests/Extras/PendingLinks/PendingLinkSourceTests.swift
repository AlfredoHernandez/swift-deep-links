//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct PendingLinkSourceTests {
	private let protectedURL = URL(string: "myapp://account/settings")!

	@Test(arguments: [DeepLinkContext.Source.customScheme, .unknown])
	func `links from any app are rejected without being saved by default`(source: DeepLinkContext.Source) async {
		let store = InMemoryPendingLinkStore()
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), protectedHosts: ["account"], pendingLinks: store)

		await #expect(throws: DeepLinkError.unauthorizedAccess(protectedURL)) {
			try await sut.intercept(DeepLinkRequest(url: protectedURL, context: DeepLinkContext(source: source)))
		}
		#expect(await store.takeAll().isEmpty)
	}

	@Test(arguments: [DeepLinkContext.Source.universalLink, .handoff, .notification, .spotlight, .shortcut, .intent])
	func `links from verified or app-owned sources are saved by default`(source: DeepLinkContext.Source) async {
		let store = InMemoryPendingLinkStore()
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), protectedHosts: ["account"], pendingLinks: store)

		_ = try? await sut.intercept(DeepLinkRequest(url: protectedURL, context: DeepLinkContext(source: source)))

		#expect(await store.takeAllRequests().map(\.context.source) == [source])
		#expect(AuthenticationMiddleware.defaultPendingSources == Set(DeepLinkContext.Source.allCases).subtracting([.customScheme, .unknown]))
	}

	@Test
	func `pending sources can opt in custom schemes for both rule kinds`() async {
		let store = InMemoryPendingLinkStore()
		let byHost: AuthenticationMiddleware = .authentication(
			provider: AuthenticationProviderStub(isAuthenticated: false),
			protectedHosts: ["account"],
			pendingLinks: store,
			pendingSources: [.customScheme],
		)
		let byMatcher: AuthenticationMiddleware = .authentication(
			provider: AuthenticationProviderStub(isAuthenticated: false),
			requiredFor: .all,
			pendingLinks: store,
			pendingSources: [.customScheme],
		)
		let custom = DeepLinkRequest(url: protectedURL, context: DeepLinkContext(source: .customScheme))
		let universal = DeepLinkRequest(url: protectedURL, context: DeepLinkContext(source: .universalLink))

		_ = try? await byHost.intercept(custom)
		_ = try? await byMatcher.intercept(universal)

		#expect(await store.takeAllRequests().map(\.context.source) == [.customScheme])
	}

	// MARK: - Resume

	@Test
	func `resumed links are marked so a confirmation can be required`() async throws {
		let store = InMemoryPendingLinkStore()
		let auth = SignInSwitch()
		let confirmation = CollectingConfirmation(approves: true)
		let handler = CollectingHandler<TestRoute>()
		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(ImmediateParser(routes: [.route1]))
			.handler(handler)
			.middleware(
				.authentication(provider: auth, protectedHosts: ["account"], pendingLinks: store),
				.confirmation(provider: confirmation, requiredFor: .resumedPendingLinks, timeout: nil),
			)
			.build()

		await coordinator.handle(url: protectedURL, context: DeepLinkContext(source: .universalLink))
		auth.signIn()
		await coordinator.resumePendingLinks(from: store)

		#expect(confirmation.requests.map(\.context.isResumedPendingLink) == [true])
		#expect(handler.handledContexts.map(\.isResumedPendingLink) == [true])
	}

	@Test
	func `links handled directly are not marked as resumed`() {
		let request = DeepLinkRequest(url: protectedURL, context: DeepLinkContext(source: .universalLink))

		#expect(!request.context.isResumedPendingLink)
		#expect(!DeepLinkMatcher.resumedPendingLinks.matches(request))
	}
}

private final class SignInSwitch: AuthenticationProvider {
	private let isSignedIn = OSAllocatedUnfairLock(initialState: false)

	func signIn() {
		isSignedIn.withLock { $0 = true }
	}

	func isAuthenticated() -> Bool {
		isSignedIn.withLock { $0 }
	}
}
