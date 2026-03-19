//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@Suite("ProductParser")
@MainActor
struct ProductParserTests {
	@Test("Parse delivers product route on valid product URL")
	func parse_deliversProductRoute_onValidProductURL() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://product?productID=PROD-001&category=Electronics"))

		let routes = try sut.parse(from: url)

		#expect(routes.count == 1)
		#expect(routes.first?.id == AppRoute.stack(.product(productID: "PROD-001", category: "Electronics")).id)
	}

	@Test("Parse throws unsupportedHost on non-product host")
	func parse_throwsUnsupportedHost_onNonProductHost() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://unknown?productID=1"))

		#expect(throws: DeepLinkError.unsupportedHost("unknown")) {
			try sut.parse(from: url)
		}
	}

	// MARK: - Helpers

	private func makeSUT() -> ProductParser {
		ProductParser()
	}
}
