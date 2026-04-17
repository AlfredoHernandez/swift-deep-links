//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct URLNormalizationTransformerTests {
	@Test
	func `URLNormalizationTransformer normalizes URLs correctly`() throws {
		let testURL = try #require(URL(string: "testapp://test//path?param1=value1&param2=&param3=value3"))
		let transformer = URLNormalizationTransformer()

		let result = try transformer.transform(testURL)

		#expect(result.path == "/path")
		#expect(result.query?.contains("param1=value1") == true)
		#expect(result.query?.contains("param2=") == false) // Empty param removed
		#expect(result.query?.contains("param3=value3") == true)
	}

	@Test
	func `URLNormalizationTransformer handles URLs without query parameters`() throws {
		let testURL = try #require(URL(string: "testapp://test//path"))
		let transformer = URLNormalizationTransformer()

		let result = try transformer.transform(testURL)

		#expect(result.path == "/path")
		#expect(result.query == nil)
	}

	@Test
	func `URLNormalizationTransformer handles URLs with empty path`() throws {
		let testURL = try #require(URL(string: "testapp://host"))
		let transformer = URLNormalizationTransformer()

		let result = try transformer.transform(testURL)

		#expect(result.path == "")
		#expect(result.host == "host")
	}
}
