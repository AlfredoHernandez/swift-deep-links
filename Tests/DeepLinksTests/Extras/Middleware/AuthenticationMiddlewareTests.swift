//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct AuthenticationMiddlewareTests {
	@Test
	func `AuthenticationMiddleware allows requests for unprotected hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://public"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected", "private"],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware allows requests for protected hosts when authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware blocks requests for protected hosts when not authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("protected"))
		}
	}

	@Test
	func `AuthenticationMiddleware handles URLs without host`() async throws {
		let testURL = try #require(URL(string: "testapp://"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	// MARK: - Strategy Tests

	@Test
	func `AuthenticationMiddleware with strict strategy blocks requests for protected hosts when not authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .strict,
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("protected"))
		}
	}

	@Test
	func `AuthenticationMiddleware with strict strategy allows requests for protected hosts when authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .strict,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with permissive strategy allows all requests`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .permissive,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with permissive strategy allows requests even when not authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://private"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["private", "protected"],
			strategy: .permissive,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with standard strategy allows requests for unprotected hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://public"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with standard strategy blocks requests for protected hosts when not authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("protected"))
		}
	}

	@Test
	func `AuthenticationMiddleware with standard strategy allows requests for protected hosts when authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let authStub = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with standard strategy handles URLs without host`() async throws {
		let testURL = try #require(URL(string: "testapp://"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with schemeBased strategy blocks requests for protected schemes when not authenticated`() async throws {
		let testURL = try #require(URL(string: "https://example.com"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["https"], // Using as scheme
			strategy: .schemeBased,
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("https"))
		}
	}

	@Test
	func `AuthenticationMiddleware with schemeBased strategy allows requests for protected schemes when authenticated`() async throws {
		let testURL = try #require(URL(string: "https://example.com"))
		let authStub = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["https"], // Using as scheme
			strategy: .schemeBased,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with schemeBased strategy allows requests for unprotected schemes`() async throws {
		let testURL = try #require(URL(string: "http://example.com"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["https"], // Only https is protected
			strategy: .schemeBased,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with schemeBased strategy handles URLs without scheme`() async throws {
		let testURL = try #require(URL(string: "://example.com"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: ["https"],
			strategy: .schemeBased,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	// MARK: - Edge Cases

	@Test
	func `AuthenticationMiddleware with standard strategy handles empty protected hosts`() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: [],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `AuthenticationMiddleware with strict strategy requires authentication for all URLs`() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let authStub = AuthenticationProviderStub(isAuthenticated: false)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: [],
			strategy: .strict,
		)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected unauthorized access error")
		} catch let error as DeepLinkError {
			#expect(error == .unauthorizedAccess("anyhost"))
		}
	}

	@Test
	func `AuthenticationMiddleware with strict strategy allows all URLs when authenticated`() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let authStub = AuthenticationProviderStub(isAuthenticated: true)
		let middleware = AuthenticationMiddleware(
			authProvider: authStub,
			protectedHosts: [],
			strategy: .strict,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	// MARK: - PermissiveAuthenticationProvider Tests

	@Test
	func `PermissiveAuthenticationProvider always returns true for authentication`() {
		let provider = PermissiveAuthenticationProvider()

		let isAuthenticated = provider.isAuthenticated()

		#expect(isAuthenticated == true)
	}

	@Test
	func `PermissiveAuthenticationProvider returns consistent authentication status`() {
		let provider = PermissiveAuthenticationProvider()

		// Test multiple calls to ensure consistency
		let firstCall = provider.isAuthenticated()
		let secondCall = provider.isAuthenticated()
		let thirdCall = provider.isAuthenticated()

		#expect(firstCall == true)
		#expect(secondCall == true)
		#expect(thirdCall == true)
		#expect(firstCall == secondCall)
		#expect(secondCall == thirdCall)
	}

	@Test
	func `PermissiveAuthenticationProvider works with AuthenticationMiddleware`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let provider = PermissiveAuthenticationProvider()
		let middleware = AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `PermissiveAuthenticationProvider works with strict strategy`() async throws {
		let testURL = try #require(URL(string: "testapp://anyhost"))
		let provider = PermissiveAuthenticationProvider()
		let middleware = AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: [],
			strategy: .strict,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `PermissiveAuthenticationProvider works with standard strategy`() async throws {
		let testURL = try #require(URL(string: "testapp://protected"))
		let provider = PermissiveAuthenticationProvider()
		let middleware = AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: ["protected"],
			strategy: .standard,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `PermissiveAuthenticationProvider works with schemeBased strategy`() async throws {
		let testURL = try #require(URL(string: "https://example.com"))
		let provider = PermissiveAuthenticationProvider()
		let middleware = AuthenticationMiddleware(
			authProvider: provider,
			protectedHosts: ["https"],
			strategy: .schemeBased,
		)

		let result = try await middleware.intercept(testURL)

		#expect(result == testURL)
	}

	@Test
	func `PermissiveAuthenticationProvider is thread-safe`() async {
		let provider = PermissiveAuthenticationProvider()

		// Test concurrent access
		await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 10 {
				group.addTask {
					provider.isAuthenticated()
				}
			}

			var results: [Bool] = []
			for await result in group {
				results.append(result)
			}

			// All results should be true
			#expect(results.count == 10)
			#expect(results.allSatisfy { $0 == true })
		}
	}

	@Test
	func `PermissiveAuthenticationProvider can be used as AuthenticationProvider protocol`() {
		let provider: AuthenticationProvider = PermissiveAuthenticationProvider()

		let isAuthenticated = provider.isAuthenticated()

		#expect(isAuthenticated == true)
	}
}
