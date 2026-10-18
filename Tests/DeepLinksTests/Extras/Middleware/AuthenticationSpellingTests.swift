//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct AuthenticationSpellingTests {
	@Test(arguments: [
		"myapp://account/x",
		"myapp://ACCOUNT/x",
		"myapp://account./x",
		"myapp://account%2e/x",
		"myapp://%61ccount/x",
		"myapp:///account/x",
		"myapp:/account/x",
		"myapp:account/x",
	])
	func `standard strategy protects every spelling of a protected host`(link: String) async throws {
		let url = try #require(URL(string: link))
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), protectedHosts: ["account"])

		await #expect(throws: DeepLinkError.unauthorizedAccess(url)) {
			_ = try await sut.intercept(url: url)
		}
	}

	@Test(arguments: [
		"myapp://public/account",
		"myapp:///public/account",
		"myapp:public/account",
		"https://example.com/account",
		"myapp://accounts/x",
	])
	func `standard strategy leaves other hosts public`(link: String) async throws {
		let url = try #require(URL(string: link))
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), protectedHosts: ["account"])

		#expect(try await sut.intercept(url: url) == url)
	}

	@Test
	func `standard strategy compares protected hosts case-insensitively`() async throws {
		let url = try #require(URL(string: "https://secure.example.com/profile"))
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), protectedHosts: ["Secure.Example.com."])

		await #expect(throws: DeepLinkError.unauthorizedAccess(url)) {
			_ = try await sut.intercept(url: url)
		}
	}

	// MARK: - Matcher Rules

	@Test
	func `matcher rule protects the links it selects`() async throws {
		let admin = try #require(URL(string: "https://example.com/admin/users"))
		let help = try #require(URL(string: "https://example.com/help"))
		let sut = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: false), requiredFor: .paths(["/admin"]))

		await #expect(throws: DeepLinkError.unauthorizedAccess(admin)) {
			_ = try await sut.intercept(url: admin)
		}
		#expect(try await sut.intercept(url: help) == help)
	}

	@Test
	func `matcher rule lets authenticated users through and saves rejected links`() async throws {
		let admin = try #require(URL(string: "https://example.com/admin"))
		let pendingLinks = InMemoryPendingLinkStore()
		let rejecting: AuthenticationMiddleware = .authentication(
			provider: AuthenticationProviderStub(isAuthenticated: false),
			requiredFor: .paths(["/admin"]),
			pendingLinks: pendingLinks,
			pendingSources: Set(DeepLinkContext.Source.allCases),
		)
		let admitting = AuthenticationMiddleware(authProvider: AuthenticationProviderStub(isAuthenticated: true), requiredFor: .paths(["/admin"]))

		_ = try? await rejecting.intercept(url: admin)

		#expect(await pendingLinks.takeAll() == [admin])
		#expect(try await admitting.intercept(url: admin) == admin)
	}

	// MARK: - Route Rules

	@Test
	func `authenticated handler rejects a protected route for a signed-out user`() async throws {
		let blank = try #require(URL(string: "about:blank"))
		let inner = CollectingHandler<TestRoute>()
		let sut = inner.requiringAuthentication(for: .routes { $0 == .route1 }, provider: AuthenticationProviderStub(isAuthenticated: false))

		await #expect(throws: DeepLinkError.unauthorizedAccess(blank)) {
			try await sut.handle(.route1, context: .unknown)
		}
		#expect(inner.handledRoutes.isEmpty)
	}

	@Test
	func `authenticated handler runs unprotected routes and routes of signed-in users`() async throws {
		let inner = CollectingHandler<TestRoute>()
		let signedOut = AuthenticatedHandler(inner, requiredFor: .routes { $0 == .route1 }, provider: AuthenticationProviderStub(isAuthenticated: false))
		let signedIn = inner.requiringAuthentication(for: .all, provider: AuthenticationProviderStub(isAuthenticated: true))

		try await signedOut.handle(.route2, context: .unknown)
		try await signedIn.handle(.route1, context: .unknown)

		#expect(inner.handledRoutes == [.route2, .route1])
	}

	@Test
	func `authenticated handler reports the routed URL inside a coordinator`() async throws {
		let url = try #require(URL(string: "myapp:///account"))
		let inner = CollectingHandler<TestRoute>()
		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(ImmediateParser<TestRoute>(routes: [.route1]))
			.handler(inner.requiringAuthentication(for: .all, provider: AuthenticationProviderStub(isAuthenticated: false)))
			.build()

		let result = await coordinator.handle(url: url)

		#expect(result.errors.contains { ($0 as? DeepLinkError) == .unauthorizedAccess(url) })
		#expect(inner.handledRoutes.isEmpty)
	}
}
