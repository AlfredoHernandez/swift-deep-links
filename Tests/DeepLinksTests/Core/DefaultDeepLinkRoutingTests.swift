//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DefaultDeepLinkRoutingTests {
	@Test
	func `DefaultDeepLinkRouting route returns routes from first successful parser`() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1, .route2])
		let parser3 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route3])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2, parser3])
		let url = try #require(URL(string: "test://success"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1, .route2])
		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
		#expect(parser3.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting route returns routes from second parser when first fails`() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2])
		let url = try #require(URL(string: "test://second"))

		let result = try await routing.route(from: url)

		#expect(result == [.route2])
		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
	}

	/// Covers the happy paths where a single parser returns 0, 1, or N routes.
	/// Parameterised to avoid duplicating the setup + single-parser harness
	/// across three near-identical tests.
	@Test(arguments: [
		[TestRoute](),
		[TestRoute.route1],
		[TestRoute.route1, .route2, .route3],
	] as [[TestRoute]])
	func `DefaultDeepLinkRouting route returns whatever the single parser produces`(routes: [TestRoute]) async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: routes)
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://routes-\(routes.count)"))

		let result = try await routing.route(from: url)

		#expect(result == routes)
		#expect(parser.parseCalledWith == url)
	}

	@Test
	func `DefaultDeepLinkRouting route throws parsingFailed when all parsers fail`() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser3 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2, parser3])
		let url = try #require(URL(string: "test://allfail"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: url)
		}

		guard case let .parsingFailed(thrownURL, underlyingErrors) = error else {
			Issue.record("Expected .parsingFailed, got \(String(describing: error))")
			return
		}
		#expect(thrownURL == url)
		#expect(underlyingErrors.count == 3)

		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
		#expect(parser3.parseCalledWith == url)
	}

	@Test
	func `DefaultDeepLinkRouting route throws parsingFailed carrying the parser errors in order`() async throws {
		let parser1 = ThrowingParserStub<TestRoute>(error: DeepLinkError.missingRequiredParameter("userId"))
		let parser2 = ThrowingParserStub<TestRoute>(error: DeepLinkError.missingRequiredParameter("productId"))
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2])
		let url = try #require(URL(string: "test://chain"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: url)
		}

		guard case let .parsingFailed(_, underlyingErrors) = error else {
			Issue.record("Expected .parsingFailed, got \(String(describing: error))")
			return
		}
		let deepLinkErrors = underlyingErrors.compactMap { $0 as? DeepLinkError }
		#expect(deepLinkErrors == [
			.missingRequiredParameter("userId"),
			.missingRequiredParameter("productId"),
		])
	}

	@Test
	func `DefaultDeepLinkRouting flattens nested parsingFailed from a delegating parser`() async throws {
		let nestedURL = try #require(URL(string: "test://inner"))
		let leafError1 = DeepLinkError.missingRequiredParameter("userId")
		let leafError2 = DeepLinkError.missingRequiredParameter("productId")
		let delegatingParser = ThrowingParserStub<TestRoute>(error: DeepLinkError.parsingFailed(
			url: nestedURL,
			underlyingErrors: [leafError1, leafError2],
		))
		let trailingParser = ThrowingParserStub<TestRoute>(error: DeepLinkError.unsupportedHost("settings"))
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [delegatingParser, trailingParser])
		let url = try #require(URL(string: "test://outer"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: url)
		}

		guard case let .parsingFailed(thrownURL, underlyingErrors) = error else {
			Issue.record("Expected .parsingFailed, got \(String(describing: error))")
			return
		}
		#expect(thrownURL == url)
		let deepLinkErrors = underlyingErrors.compactMap { $0 as? DeepLinkError }
		#expect(deepLinkErrors == [
			leafError1,
			leafError2,
			.unsupportedHost("settings"),
		])
	}

	@Test
	func `DefaultDeepLinkRouting route throws routeNotFound error when no parsers provided`() async throws {
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [])
		let url = try #require(URL(string: "test://noparsers"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: url)
		}

		#expect(error == .routeNotFound(url))
	}

	/// Runs `body`, asserts it threw a `DeepLinkError`, and returns the error
	/// so the test can pattern-match on it. Replaces the older
	/// `do { #expect(Bool(false)) } catch { Issue.record } } ` idiom with a
	/// single explicit fail-on-success plus a typed return.
	private func expectDeepLinkError(
		sourceLocation: SourceLocation = #_sourceLocation,
		_ body: () async throws -> Void,
	) async -> DeepLinkError? {
		do {
			try await body()
			Issue.record("Expected DeepLinkError but the body returned normally.", sourceLocation: sourceLocation)
			return nil
		} catch let error as DeepLinkError {
			return error
		} catch {
			Issue.record("Expected DeepLinkError, got \(error)", sourceLocation: sourceLocation)
			return nil
		}
	}

	@Test(arguments: [
		DeepLinkError.securityViolation("Path traversal is not allowed"),
		DeepLinkError.blockedURL(URL(string: "test://blocked")!),
	])
	func `DefaultDeepLinkRouting rethrows security errors without trying later parsers`(error: DeepLinkError) async throws {
		let lax = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [ThrowingParserStub(error: error), lax])
		let url = try #require(URL(string: "test://files/%2e%2e/admin"))

		await #expect(throws: error) {
			try await routing.route(from: url)
		}
		#expect(lax.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting rethrows a security error nested in parsingFailed`() async throws {
		let url = try #require(URL(string: "test://nested"))
		let violation = DeepLinkError.securityViolation("nested")
		let delegating = ThrowingParserStub<TestRoute>(error: .parsingFailed(url: url, underlyingErrors: [TestParserError.parserError, violation]))
		let lax = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [delegating, lax])

		await #expect(throws: violation) {
			try await routing.route(from: url)
		}
		#expect(lax.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting stops at a path pattern traversal rejection`() async throws {
		let strict = try PathPatternParser<TestRoute>("/files/*") { _ in .route1 }
		let lax = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [strict, lax])
		let url = try #require(URL(string: "https://example.com/files/%2e%2e/admin"))

		await #expect(throws: DeepLinkError.securityViolation("Path traversal is not allowed")) {
			try await routing.route(from: url)
		}
		#expect(lax.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting route continues trying parsers after first failure`() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser3 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route3])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2, parser3])
		let url = try #require(URL(string: "test://third"))

		let result = try await routing.route(from: url)

		#expect(result == [.route3])
		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
		#expect(parser3.parseCalledWith == url)
	}

	@Test
	func `DefaultDeepLinkRouting route stops at first successful parser`() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let parser3 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route3])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2, parser3])
		let url = try #require(URL(string: "test://first"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1])
		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == nil)
		#expect(parser3.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting route handles single parser successfully`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1, .route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://singleparser"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1, .route2])
		#expect(parser.parseCalledWith == url)
	}

	@Test
	func `DefaultDeepLinkRouting route handles single parser failure`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://singlefail"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: url)
		}

		guard case let .parsingFailed(thrownURL, underlyingErrors) = error else {
			Issue.record("Expected .parsingFailed, got \(String(describing: error))")
			return
		}
		#expect(thrownURL == url)
		#expect(underlyingErrors.count == 1)

		#expect(parser.parseCalledWith == url)
	}

	@Test
	func `DefaultDeepLinkRouting route validates URL structure before parsing`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let invalidURL = try #require(URL(string: "not-a-valid-url"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: invalidURL)
		}

		#expect(error == .invalidURL(invalidURL))
		#expect(parser.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting route handles URL without scheme`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let urlWithoutScheme = try #require(URL(string: "//host/path"))

		let error = await expectDeepLinkError {
			_ = try await routing.route(from: urlWithoutScheme)
		}

		#expect(error == .invalidURL(urlWithoutScheme))
		#expect(parser.parseCalledWith == nil)
	}

	@Test
	func `DefaultDeepLinkRouting route handles URL with empty host`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let urlWithEmptyHost = try #require(URL(string: "test://"))

		let result = try await routing.route(from: urlWithEmptyHost)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == urlWithEmptyHost)
	}

	@Test
	func `DefaultDeepLinkRouting route handles complex URL structure`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let complexURL = try #require(URL(string: "myapp://user:pass@host:8080/path/to/resource?param1=value1&param2=value2#fragment"))

		let result = try await routing.route(from: complexURL)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == complexURL)
	}

	@Test
	func `DefaultDeepLinkRouting route handles URL with special characters`() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let specialURL = try #require(URL(string: "myapp://special?title=News%20%26%20Updates&emoji=🚀"))

		let result = try await routing.route(from: specialURL)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == specialURL)
	}
}
