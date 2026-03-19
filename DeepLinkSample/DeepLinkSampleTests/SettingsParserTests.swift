//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinkSample
import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@Suite("SettingsParser")
@MainActor
struct SettingsParserTests {
	@Test("Parse delivers settings route on valid settings URL")
	func parse_deliversSettingsRoute_onValidSettingsURL() throws {
		let sut = makeSUT()
		let url = try #require(URL(string: "deeplink://settings?section=account"))

		let routes = try sut.parse(from: url)

		#expect(routes.count == 1)
		#expect(routes.first?.id == AppRoute.stack(.settings(section: "account")).id)
	}

	@Test("Parse throws unsupportedHost on non-settings host")
	func parse_throwsUnsupportedHost_onNonSettingsHost() throws {
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
