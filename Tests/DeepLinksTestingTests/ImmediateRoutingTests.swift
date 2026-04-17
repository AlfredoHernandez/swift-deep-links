//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Testing

struct ImmediateRoutingTests {
	@Test
	func `returns preconfigured routes for any URL`() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [.routeA, .routeB])

		let result = try await sut.route(from: testURL)

		#expect(result == [.routeA, .routeB])
	}

	@Test
	func `returns same routes regardless of URL`() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [.routeA])

		let first = try await sut.route(from: testURL)
		let second = try await sut.route(from: anotherURL)

		#expect(first == second)
	}

	@Test
	func `returns empty array when configured with no routes`() async throws {
		let sut = ImmediateRouting<TestRoute>(routes: [])

		let result = try await sut.route(from: testURL)

		#expect(result.isEmpty)
	}

	@Test
	func `throws the exact configured error`() async {
		let sut = ImmediateRouting<TestRoute>(error: DeepLinkError.routeNotFound("test"))

		await #expect(throws: DeepLinkError.routeNotFound("test")) {
			try await sut.route(from: testURL)
		}
	}
}
