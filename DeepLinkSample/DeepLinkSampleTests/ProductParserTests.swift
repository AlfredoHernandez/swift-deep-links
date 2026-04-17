//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import Foundation
import Testing

@MainActor
struct ProductParserTests {
	@Test
	func `Parse delivers product route on valid product URL`() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://product?productID=PROD-001&category=Electronics"))

		let routes = try sut.parse(from: url)

		#expect(routes.count == 1)
		#expect(routes.first?.id == AppRoute.stack(.product(productID: "PROD-001", category: "Electronics")).id)
	}

	@Test
	func `Parse throws unsupportedHost on non-product host`() throws {
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
