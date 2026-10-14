//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

import DeepLinksTesting
import Foundation
import Testing

struct ManualDateProviderTests {
	@Test
	func `starts at the given instant`() {
		let start = Date(timeIntervalSince1970: 42)
		let sut = ManualDateProvider(now: start)

		#expect(sut.now == start)
		#expect(sut.dateProvider() == start)
	}

	@Test
	func `default start is a fixed instant`() {
		#expect(ManualDateProvider().now == ManualDateProvider().now)
	}

	@Test
	func `advance moves time forward and backward`() {
		let sut = ManualDateProvider(now: Date(timeIntervalSince1970: 100))

		sut.advance(by: 30)
		#expect(sut.now == Date(timeIntervalSince1970: 130))

		sut.advance(by: -50)
		#expect(sut.now == Date(timeIntervalSince1970: 80))
	}

	@Test
	func `setting now is visible through a provider captured earlier`() {
		let sut = ManualDateProvider()
		let provider = sut.dateProvider

		sut.now = Date(timeIntervalSince1970: 7)

		#expect(provider() == Date(timeIntervalSince1970: 7))
	}

	@Test
	func `concurrent advances are not lost`() async {
		let sut = ManualDateProvider(now: Date(timeIntervalSince1970: 0))

		await withTaskGroup(of: Void.self) { group in
			for _ in 0 ..< 100 {
				group.addTask { sut.advance(by: 1) }
			}
		}

		#expect(sut.now == Date(timeIntervalSince1970: 100))
	}
}
