//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinks
import DeepLinksTesting
import Testing

@Suite("ImmediateParser")
struct ImmediateParserTests {
	@Test("returns preconfigured routes for any URL")
	func parse_deliversPreconfiguredRoutes() async throws {
		let sut = ImmediateParser<TestRoute>(routes: [.routeA])

		let result = try await sut.parse(from: testURL)

		#expect(result == [.routeA])
	}

	@Test("returns same routes regardless of URL")
	func parse_ignoresURLAndReturnsSameRoutes() async throws {
		let sut = ImmediateParser<TestRoute>(routes: [.routeB])

		let first = try await sut.parse(from: testURL)
		let second = try await sut.parse(from: anotherURL)

		#expect(first == second)
	}

	@Test("throws the exact configured error")
	func parse_throwsConfiguredError() async {
		let sut = ImmediateParser<TestRoute>(error: DeepLinkError.unsupportedHost("test"))

		await #expect(throws: DeepLinkError.unsupportedHost("test")) {
			try await sut.parse(from: testURL)
		}
	}
}
