//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Foundation
import Testing

struct URLFuzzCorpusTests {
	@Test(arguments: URLFuzzCase.Category.allCases)
	func `every category has cases`(category: URLFuzzCase.Category) {
		#expect(!URLFuzzCorpus.hostile(category).isEmpty)
	}

	@Test
	func `all cases combine every category`() {
		let all = URLFuzzCorpus.hostile()

		#expect(Set(all.map(\.category)) == Set(URLFuzzCase.Category.allCases))
		#expect(all.count == URLFuzzCase.Category.allCases.map { URLFuzzCorpus.hostile($0).count }.reduce(0, +))
	}

	@Test
	func `the default corpus keeps every case`() {
		#expect(URLFuzzCorpus.hostile().count == 36)
	}

	@Test
	func `cases target the given scheme and host`() {
		let cases = URLFuzzCorpus.hostile(.traversal, scheme: "myapp", host: "open")

		#expect(cases.allSatisfy { $0.url.scheme == "myapp" && $0.url.host() == "open" })
	}

	@Test
	func `case names are unique`() {
		let names = URLFuzzCorpus.hostile().map(\.description)

		#expect(Set(names).count == names.count)
	}

	@Test
	func `oversize cases exceed the recommended limits`() {
		let cases = URLFuzzCorpus.hostile(.oversize)

		#expect(cases.contains { $0.url.absoluteString.count > 8192 })
	}
}
