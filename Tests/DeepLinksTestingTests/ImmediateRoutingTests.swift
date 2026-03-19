//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Testing

@Suite("ImmediateRouting")
struct ImmediateRoutingTests {
	@Test("returns preconfigured routes for any URL")
	func route_deliversPreconfiguredRoutes() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [.routeA, .routeB])

		let result = try await sut.route(from: testURL)

		#expect(result == [.routeA, .routeB])
	}

	@Test("returns same routes regardless of URL")
	func route_ignoresURLAndReturnsSameRoutes() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [.routeA])

		let first = try await sut.route(from: testURL)
		let second = try await sut.route(from: anotherURL)

		#expect(first == second)
	}

	@Test("returns empty array when configured with no routes")
	func route_deliversEmptyOnEmptyConfiguration() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [])

		let result = try await sut.route(from: testURL)

		#expect(result.isEmpty)
	}

	@Test("throws the exact configured error")
	func route_throwsConfiguredError() async {
		let sut = ImmediateRouting<TestRoute>(error: DeepLinkError.routeNotFound("test"))

		await #expect(throws: DeepLinkError.routeNotFound("test")) {
			try await sut.route(from: testURL)
		}
	}
}
