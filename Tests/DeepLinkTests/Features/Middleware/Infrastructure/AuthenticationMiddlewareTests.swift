//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("AuthenticationMiddleware Tests")
struct AuthenticationMiddlewareTests {
    @Test("AuthenticationMiddleware allows requests for unprotected hosts")
    func authenticationMiddleware_allowsRequestsForUnprotectedHosts() async throws {
        let testURL = URL(string: "testapp://public")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected", "private"],
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware allows requests for protected hosts when authenticated")
    func authenticationMiddleware_allowsRequestsForProtectedHostsWhenAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: true)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware blocks requests for protected hosts when not authenticated")
    func authenticationMiddleware_blocksRequestsForProtectedHostsWhenNotAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: false)
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

    @Test("AuthenticationMiddleware handles URLs without host")
    func authenticationMiddleware_handlesURLsWithoutHost() async throws {
        let testURL = URL(string: "testapp://")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - Strategy Tests

    @Test("AuthenticationMiddleware with strict strategy blocks requests for protected hosts when not authenticated")
    func authenticationMiddleware_withStrictStrategy_blocksRequestsForProtectedHostsWhenNotAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: false)
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

    @Test("AuthenticationMiddleware with strict strategy allows requests for protected hosts when authenticated")
    func authenticationMiddleware_withStrictStrategy_allowsRequestsForProtectedHostsWhenAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: true)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
            strategy: .strict,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with permissive strategy allows all requests")
    func authenticationMiddleware_withPermissiveStrategy_allowsAllRequests() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
            strategy: .permissive,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with permissive strategy allows requests even when not authenticated")
    func authenticationMiddleware_withPermissiveStrategy_allowsRequestsEvenWhenNotAuthenticated() async throws {
        let testURL = URL(string: "testapp://private")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["private", "protected"],
            strategy: .permissive,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with standard strategy allows requests for unprotected hosts")
    func authenticationMiddleware_withHostBasedStrategy_allowsRequestsForUnprotectedHosts() async throws {
        let testURL = URL(string: "testapp://public")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with standard strategy blocks requests for protected hosts when not authenticated")
    func authenticationMiddleware_withHostBasedStrategy_blocksRequestsForProtectedHostsWhenNotAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: false)
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

    @Test("AuthenticationMiddleware with standard strategy allows requests for protected hosts when authenticated")
    func authenticationMiddleware_withHostBasedStrategy_allowsRequestsForProtectedHostsWhenAuthenticated() async throws {
        let testURL = URL(string: "testapp://protected")!
        let authStub = AuthenticationStub(isAuthenticated: true)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with standard strategy handles URLs without host")
    func authenticationMiddleware_withHostBasedStrategy_handlesURLsWithoutHost() async throws {
        let testURL = URL(string: "testapp://")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["protected"],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with schemeBased strategy blocks requests for protected schemes when not authenticated")
    func authenticationMiddleware_withSchemeBasedStrategy_blocksRequestsForProtectedSchemesWhenNotAuthenticated() async throws {
        let testURL = URL(string: "https://example.com")!
        let authStub = AuthenticationStub(isAuthenticated: false)
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

    @Test("AuthenticationMiddleware with schemeBased strategy allows requests for protected schemes when authenticated")
    func authenticationMiddleware_withSchemeBasedStrategy_allowsRequestsForProtectedSchemesWhenAuthenticated() async throws {
        let testURL = URL(string: "https://example.com")!
        let authStub = AuthenticationStub(isAuthenticated: true)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["https"], // Using as scheme
            strategy: .schemeBased,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with schemeBased strategy allows requests for unprotected schemes")
    func authenticationMiddleware_withSchemeBasedStrategy_allowsRequestsForUnprotectedSchemes() async throws {
        let testURL = URL(string: "http://example.com")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["https"], // Only https is protected
            strategy: .schemeBased,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with schemeBased strategy handles URLs without scheme")
    func authenticationMiddleware_withSchemeBasedStrategy_handlesURLsWithoutScheme() async throws {
        let testURL = URL(string: "://example.com")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: ["https"],
            strategy: .schemeBased,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - Edge Cases

    @Test("AuthenticationMiddleware with standard strategy handles empty protected hosts")
    func authenticationMiddleware_withStandardStrategy_handlesEmptyProtectedHosts() async throws {
        let testURL = URL(string: "testapp://anyhost")!
        let authStub = AuthenticationStub(isAuthenticated: false)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: [],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("AuthenticationMiddleware with strict strategy requires authentication for all URLs")
    func authenticationMiddleware_withStrictStrategy_requiresAuthenticationForAllURLs() async throws {
        let testURL = URL(string: "testapp://anyhost")!
        let authStub = AuthenticationStub(isAuthenticated: false)
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

    @Test("AuthenticationMiddleware with strict strategy allows all URLs when authenticated")
    func authenticationMiddleware_withStrictStrategy_allowsAllURLsWhenAuthenticated() async throws {
        let testURL = URL(string: "testapp://anyhost")!
        let authStub = AuthenticationStub(isAuthenticated: true)
        let middleware = AuthenticationMiddleware(
            authProvider: authStub,
            protectedHosts: [],
            strategy: .strict,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    // MARK: - PermissiveAuthenticationProvider Tests

    @Test("PermissiveAuthenticationProvider always returns true for authentication")
    func permissiveAuthenticationProvider_alwaysReturnsTrueForAuthentication() async throws {
        let provider = PermissiveAuthenticationProvider()

        let isAuthenticated = await provider.isAuthenticated()

        #expect(isAuthenticated == true)
    }

    @Test("PermissiveAuthenticationProvider returns consistent authentication status")
    func permissiveAuthenticationProvider_returnsConsistentAuthenticationStatus() async throws {
        let provider = PermissiveAuthenticationProvider()

        // Test multiple calls to ensure consistency
        let firstCall = await provider.isAuthenticated()
        let secondCall = await provider.isAuthenticated()
        let thirdCall = await provider.isAuthenticated()

        #expect(firstCall == true)
        #expect(secondCall == true)
        #expect(thirdCall == true)
        #expect(firstCall == secondCall)
        #expect(secondCall == thirdCall)
    }

    @Test("PermissiveAuthenticationProvider works with AuthenticationMiddleware")
    func defaultAuthenticationProvider_worksWithAuthenticationMiddleware() async throws {
        let testURL = URL(string: "testapp://protected")!
        let provider = PermissiveAuthenticationProvider()
        let middleware = AuthenticationMiddleware(
            authProvider: provider,
            protectedHosts: ["protected"],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("PermissiveAuthenticationProvider works with strict strategy")
    func defaultAuthenticationProvider_worksWithStrictStrategy() async throws {
        let testURL = URL(string: "testapp://anyhost")!
        let provider = PermissiveAuthenticationProvider()
        let middleware = AuthenticationMiddleware(
            authProvider: provider,
            protectedHosts: [],
            strategy: .strict,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("PermissiveAuthenticationProvider works with standard strategy")
    func defaultAuthenticationProvider_worksWithHostBasedStrategy() async throws {
        let testURL = URL(string: "testapp://protected")!
        let provider = PermissiveAuthenticationProvider()
        let middleware = AuthenticationMiddleware(
            authProvider: provider,
            protectedHosts: ["protected"],
            strategy: .standard,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("PermissiveAuthenticationProvider works with schemeBased strategy")
    func defaultAuthenticationProvider_worksWithSchemeBasedStrategy() async throws {
        let testURL = URL(string: "https://example.com")!
        let provider = PermissiveAuthenticationProvider()
        let middleware = AuthenticationMiddleware(
            authProvider: provider,
            protectedHosts: ["https"],
            strategy: .schemeBased,
        )

        let result = try await middleware.intercept(testURL)

        #expect(result == testURL)
    }

    @Test("PermissiveAuthenticationProvider is thread-safe")
    func defaultAuthenticationProvider_isThreadSafe() async throws {
        let provider = PermissiveAuthenticationProvider()

        // Test concurrent access
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    await provider.isAuthenticated()
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

    @Test("PermissiveAuthenticationProvider can be used as AuthenticationProvider protocol")
    func defaultAuthenticationProvider_canBeUsedAsAuthenticationProviderProtocol() async throws {
        let provider: AuthenticationProvider = PermissiveAuthenticationProvider()

        let isAuthenticated = await provider.isAuthenticated()

        #expect(isAuthenticated == true)
    }

    // MARK: - Test Helpers

    private final class AuthenticationStub: AuthenticationProvider, @unchecked Sendable {
        private let isAuthenticated: Bool

        init(isAuthenticated: Bool) {
            self.isAuthenticated = isAuthenticated
        }

        func isAuthenticated() async -> Bool {
            isAuthenticated
        }
    }
}
