//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct CoordinatorBuilderParserShortcutTests {
	@Test
	func `parser shortcut produces a working coordinator`() async throws {
		let url = try #require(URL(string: "test://route1"))
		let parser = HostParser(host: "route1", route: TestRoute.route1)
		let handler = DeepLinkHandlerSpy<TestRoute>()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(parser)
			.handler(handler)
			.build()

		_ = await coordinator.handle(url: url)

		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `parser shortcut composes with handler dot-shorthand from factory`() async throws {
		let url = try #require(URL(string: "test://route1"))
		let collector = CollectingHandler<TestRoute>()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(.from { _ in TestRoute.route1 })
			.handler(.from { route in try await collector.handle(route) })
			.build()

		_ = await coordinator.handle(url: url)

		#expect(collector.handledRoutes == [.route1])
	}

	/// Pins that both the array and variadic `parsers(...)` overloads
	/// plumb the parsers through to `DefaultDeepLinkRouting` in the same
	/// order, so the fluent API is overload-agnostic.
	@Test(arguments: Self.parsersOverloadCases)
	func `parsers overloads both try parsers in order`(overload: ParsersOverload) async throws {
		let url = try #require(URL(string: "test://route2"))
		let parser1 = HostParser(host: "route1", route: TestRoute.route1)
		let parser2 = HostParser(host: "route2", route: TestRoute.route2)
		let handler = DeepLinkHandlerSpy<TestRoute>()

		let coordinator = try overload.apply(DeepLinkCoordinatorBuilder<TestRoute>(), parser1, parser2)
			.handler(handler)
			.build()

		_ = await coordinator.handle(url: url)

		#expect(handler.handledRoutes == [.route2])
	}

	@Test
	func `routing is overridden when parser is called afterwards`() async throws {
		let url = try #require(URL(string: "test://route1"))
		let ignoredRouting = DeepLinkRoutingStub<TestRoute>()
		ignoredRouting.routesToReturn = [.route3]
		let parser = HostParser(host: "route1", route: TestRoute.route1)
		let handler = DeepLinkHandlerSpy<TestRoute>()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(ignoredRouting)
			.parser(parser)
			.handler(handler)
			.build()

		_ = await coordinator.handle(url: url)

		#expect(handler.handledRoutes == [.route1])
	}

	@Test
	func `parser is overridden when routing is called afterwards`() async throws {
		let url = try #require(URL(string: "test://route1"))
		let parser = HostParser(host: "route1", route: TestRoute.route1)
		let winningRouting = DeepLinkRoutingStub<TestRoute>()
		winningRouting.routesToReturn = [.route3]
		let handler = DeepLinkHandlerSpy<TestRoute>()

		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(parser)
			.routing(winningRouting)
			.handler(handler)
			.build()

		_ = await coordinator.handle(url: url)

		#expect(handler.handledRoutes == [.route3])
	}

	// MARK: - Parameterised Scenarios

	/// Captures the two `parsers(...)` overloads as data so one parameterised
	/// test can assert both route parsers in order.
	struct ParsersOverload: CustomStringConvertible {
		let name: String
		let apply: @Sendable (
			DeepLinkCoordinatorBuilder<TestRoute>,
			any DeepLinkParser<TestRoute>,
			any DeepLinkParser<TestRoute>,
		) -> DeepLinkCoordinatorBuilder<TestRoute>

		var description: String {
			name
		}
	}

	fileprivate static let parsersOverloadCases: [ParsersOverload] = [
		ParsersOverload(name: "array overload") { builder, first, second in
			builder.parsers([first, second])
		},
		ParsersOverload(name: "variadic overload") { builder, first, second in
			builder.parsers(first, second)
		},
	]
}

// MARK: - Test Doubles

private struct HostParser: DeepLinkParser {
	let host: String
	let route: TestRoute

	func parse(from url: URL) async throws -> [TestRoute] {
		guard url.host == host else {
			throw DeepLinkError.unsupportedHost(url.host ?? "")
		}
		return [route]
	}
}
