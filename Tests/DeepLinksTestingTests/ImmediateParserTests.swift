//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Testing

struct ImmediateParserTests {
	@Test
	func `returns preconfigured routes for any URL`() async throws {
		let sut = ImmediateParser<TestRoute>(routes: [.routeA])

		let result = try await sut.parse(from: testURL)

		#expect(result == [.routeA])
	}

	@Test
	func `returns same routes regardless of URL`() async throws {
		let sut = ImmediateParser<TestRoute>(routes: [.routeB])

		let first = try await sut.parse(from: testURL)
		let second = try await sut.parse(from: anotherURL)

		#expect(first == second)
	}

	@Test
	func `throws the exact configured error`() async {
		let sut = ImmediateParser<TestRoute>(error: DeepLinkError.unsupportedHost("test"))

		await #expect(throws: DeepLinkError.unsupportedHost("test")) {
			try await sut.parse(from: testURL)
		}
	}
}
