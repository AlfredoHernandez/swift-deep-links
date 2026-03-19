//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

@Suite("DefaultDeepLinkRouting Tests")
struct DefaultDeepLinkRoutingTests {
	@Test("DefaultDeepLinkRouting route returns routes from first successful parser")
	func defaultDeepLinkRouting_route_returnsRoutesFromFirstSuccessfulParser() async throws {
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

	@Test("DefaultDeepLinkRouting route returns routes from second parser when first fails")
	func defaultDeepLinkRouting_route_returnsRoutesFromSecondParserWhenFirstFails() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2])
		let url = try #require(URL(string: "test://second"))

		let result = try await routing.route(from: url)

		#expect(result == [.route2])
		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route returns empty routes array when parser succeeds with empty result")
	func defaultDeepLinkRouting_route_returnsEmptyRoutesArrayWhenParserSucceedsWithEmptyResult() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://empty"))

		let result = try await routing.route(from: url)

		#expect(result.isEmpty)
		#expect(parser.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route returns single route when parser succeeds with one route")
	func defaultDeepLinkRouting_route_returnsSingleRouteWhenParserSucceedsWithOneRoute() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://single"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route returns multiple routes when parser succeeds with multiple routes")
	func defaultDeepLinkRouting_route_returnsMultipleRoutesWhenParserSucceedsWithMultipleRoutes() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1, .route2, .route3])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://multiple"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1, .route2, .route3])
		#expect(parser.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route throws routeNotFound error when all parsers fail")
	func defaultDeepLinkRouting_route_throwsRouteNotFoundErrorWhenAllParsersFail() async throws {
		let parser1 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser2 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let parser3 = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser1, parser2, parser3])
		let url = try #require(URL(string: "test://allfail"))

		do {
			_ = try await routing.route(from: url)
			#expect(Bool(false), "Expected to throw routeNotFound error")
		} catch let error as DeepLinkError {
			#expect(error == .routeNotFound("allfail"))
		}

		#expect(parser1.parseCalledWith == url)
		#expect(parser2.parseCalledWith == url)
		#expect(parser3.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route throws routeNotFound error when no parsers provided")
	func defaultDeepLinkRouting_route_throwsRouteNotFoundErrorWhenNoParsersProvided() async throws {
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [])
		let url = try #require(URL(string: "test://noparsers"))

		do {
			_ = try await routing.route(from: url)
			#expect(Bool(false), "Expected to throw routeNotFound error")
		} catch let error as DeepLinkError {
			#expect(error == .routeNotFound("noparsers"))
		}
	}

	@Test("DefaultDeepLinkRouting route continues trying parsers after first failure")
	func defaultDeepLinkRouting_route_continuesTryingParsersAfterFirstFailure() async throws {
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

	@Test("DefaultDeepLinkRouting route stops at first successful parser")
	func defaultDeepLinkRouting_route_stopsAtFirstSuccessfulParser() async throws {
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

	@Test("DefaultDeepLinkRouting route handles single parser successfully")
	func defaultDeepLinkRouting_route_handlesSingleParserSuccessfully() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1, .route2])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://singleparser"))

		let result = try await routing.route(from: url)

		#expect(result == [.route1, .route2])
		#expect(parser.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route handles single parser failure")
	func defaultDeepLinkRouting_route_handlesSingleParserFailure() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: false)
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let url = try #require(URL(string: "test://singlefail"))

		do {
			_ = try await routing.route(from: url)
			#expect(Bool(false), "Expected to throw routeNotFound error")
		} catch let error as DeepLinkError {
			#expect(error == .routeNotFound("singlefail"))
		}

		#expect(parser.parseCalledWith == url)
	}

	@Test("DefaultDeepLinkRouting route validates URL structure before parsing")
	func defaultDeepLinkRouting_route_validatesURLStructureBeforeParsing() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let invalidURL = try #require(URL(string: "not-a-valid-url"))

		do {
			_ = try await routing.route(from: invalidURL)
			#expect(Bool(false), "Expected to throw invalidURL error")
		} catch let error as DeepLinkError {
			#expect(error == .invalidURL(invalidURL))
		}

		#expect(parser.parseCalledWith == nil)
	}

	@Test("DefaultDeepLinkRouting route handles URL without scheme")
	func defaultDeepLinkRouting_route_handlesURLWithoutScheme() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let urlWithoutScheme = try #require(URL(string: "//host/path"))

		do {
			_ = try await routing.route(from: urlWithoutScheme)
			#expect(Bool(false), "Expected to throw invalidURL error")
		} catch let error as DeepLinkError {
			#expect(error == .invalidURL(urlWithoutScheme))
		}

		#expect(parser.parseCalledWith == nil)
	}

	@Test("DefaultDeepLinkRouting route handles URL with empty host")
	func defaultDeepLinkRouting_route_handlesURLWithEmptyHost() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let urlWithEmptyHost = try #require(URL(string: "test://"))

		let result = try await routing.route(from: urlWithEmptyHost)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == urlWithEmptyHost)
	}

	@Test("DefaultDeepLinkRouting route handles complex URL structure")
	func defaultDeepLinkRouting_route_handlesComplexURLStructure() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let complexURL = try #require(URL(string: "myapp://user:pass@host:8080/path/to/resource?param1=value1&param2=value2#fragment"))

		let result = try await routing.route(from: complexURL)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == complexURL)
	}

	@Test("DefaultDeepLinkRouting route handles URL with special characters")
	func defaultDeepLinkRouting_route_handlesURLWithSpecialCharacters() async throws {
		let parser = DeepLinkParserStub<TestRoute>(shouldSucceed: true, routes: [.route1])
		let routing = DefaultDeepLinkRouting<TestRoute>(parsers: [parser])
		let specialURL = try #require(URL(string: "myapp://special?title=News%20%26%20Updates&emoji=🚀"))

		let result = try await routing.route(from: specialURL)

		#expect(result == [.route1])
		#expect(parser.parseCalledWith == specialURL)
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

	final class DeepLinkParserStub<Route: DeepLinkRoute>: DeepLinkParser, @unchecked Sendable {
		typealias Route = Route

		private let shouldSucceed: Bool
		private let routes: [Route]
		private(set) var parseCalledWith: URL?

		init(shouldSucceed: Bool, routes: [Route] = []) {
			self.shouldSucceed = shouldSucceed
			self.routes = routes
		}

		func parse(from url: URL) throws -> [Route] {
			parseCalledWith = url

			if shouldSucceed {
				return routes
			} else {
				throw TestError.parserError
			}
		}
	}

	enum TestError: Error {
		case parserError
	}
}
