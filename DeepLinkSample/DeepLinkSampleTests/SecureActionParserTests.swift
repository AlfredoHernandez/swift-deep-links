//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import Foundation
import Testing

@MainActor
struct SecureActionParserTests {
	@Test(arguments: [
		("deeplink://reset?user=42", SecureActionParser.resetRoute(userID: "42")),
		("deeplink://pay?amount=25", SecureActionParser.paymentRoute(amount: "25")),
		("deeplink://account", SecureActionParser.accountRoute),
	])
	func `Parse delivers the alert route for a secure action`(string: String, expected: AppRoute) throws {
		let url = try #require(URL(string: string))

		let routes = try SecureActionParser().parse(from: url)

		#expect(routes.map(\.id) == [expected.id])
	}

	@Test
	func `Parse throws missingRequiredParameter on a reset link without a user`() throws {
		let url = try #require(URL(string: "deeplink://reset"))

		#expect(throws: DeepLinkError.missingRequiredParameter("user")) {
			try SecureActionParser().parse(from: url)
		}
	}

	@Test
	func `Parse throws routeNotFound on other hosts so the next parser runs`() throws {
		let url = try #require(URL(string: "deeplink://product?productID=1"))

		#expect(throws: DeepLinkError.routeNotFound(url)) {
			try SecureActionParser().parse(from: url)
		}
	}
}
