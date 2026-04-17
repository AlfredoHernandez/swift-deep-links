//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct SettingsParserTests {
	@Test
	func `Parse delivers settings route on valid settings URL`() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://settings?section=account"))

		let routes = try sut.parse(from: url)

		#expect(routes.count == 1)
		#expect(routes.first?.id == AppRoute.stack(.settings(section: "account")).id)
	}

	@Test
	func `Parse throws unsupportedHost on non-settings host`() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://unknown?section=account"))

		#expect(throws: DeepLinkError.unsupportedHost("unknown")) {
			try sut.parse(from: url)
		}
	}

	// MARK: - Helpers

	private func makeSUT() -> SettingsParser {
		SettingsParser()
	}
}
