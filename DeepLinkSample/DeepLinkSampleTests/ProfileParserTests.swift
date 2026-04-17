//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct ProfileParserTests {
	@Test
	func `Parse delivers profile route on valid profile URL with name`() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://profile?userID=123&name=John"))

		let routes = try sut.parse(from: url)

		#expect(routes.count == 1)
		#expect(routes.first?.id == AppRoute.sheet(.profile(userID: "123", name: "John")).id)
	}

	@Test
	func `Parse throws unsupportedHost on non-profile host`() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://unknown?userID=1"))

		#expect(throws: DeepLinkError.unsupportedHost("unknown")) {
			try sut.parse(from: url)
		}
	}

	// MARK: - Helpers

	private func makeSUT() -> ProfileParser {
		ProfileParser()
	}
}
