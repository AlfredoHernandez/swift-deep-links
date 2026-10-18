//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct LinkDeliveryDeduplicatorTests {
	private let clock = ManualDateProvider()
	private let webLink = URL(string: "https://example.com/products/1")!

	@Test(arguments: [
		(LinkDeliveryDeduplicator.Channel.openURL, LinkDeliveryDeduplicator.Channel.userActivity),
		(.userActivity, .openURL),
	])
	func `a web link delivered by both callbacks is handled once`(first: LinkDeliveryDeduplicator.Channel, second: LinkDeliveryDeduplicator.Channel) {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)

		#expect(sut.shouldDeliver(webLink, via: first))
		clock.advance(by: 0.5)
		#expect(!sut.shouldDeliver(webLink, via: second))
	}

	@Test
	func `the same callback delivering a link again is not suppressed`() {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)

		#expect(sut.shouldDeliver(webLink, via: .openURL))
		#expect(sut.shouldDeliver(webLink, via: .openURL))
	}

	@Test
	func `a later delivery outside the window is handled`() {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)

		#expect(sut.shouldDeliver(webLink, via: .openURL))
		clock.advance(by: LinkDeliveryDeduplicator.defaultWindow)
		#expect(sut.shouldDeliver(webLink, via: .userActivity))
	}

	@Test
	func `only the duplicate is suppressed, not the next delivery`() {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)

		#expect(sut.shouldDeliver(webLink, via: .openURL))
		#expect(!sut.shouldDeliver(webLink, via: .userActivity))
		#expect(sut.shouldDeliver(webLink, via: .userActivity))
	}

	@Test
	func `custom-scheme links are never suppressed`() throws {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)
		let link = try #require(URL(string: "myapp://products/1"))

		#expect(sut.shouldDeliver(link, via: .openURL))
		#expect(sut.shouldDeliver(link, via: .userActivity))
	}

	@Test
	func `different web links are independent`() throws {
		let sut = LinkDeliveryDeduplicator(dateProvider: clock.dateProvider)
		let other = try #require(URL(string: "https://example.com/products/2"))

		#expect(sut.shouldDeliver(webLink, via: .openURL))
		#expect(sut.shouldDeliver(other, via: .userActivity))
	}
}
