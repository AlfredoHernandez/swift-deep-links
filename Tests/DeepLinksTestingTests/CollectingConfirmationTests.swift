//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct CollectingConfirmationTests {
	@Test(arguments: [true, false])
	func `returns the configured decision`(approves: Bool) async {
		let sut = CollectingConfirmation(approves: approves)

		#expect(await sut.confirm(request("myapp://pay")) == approves)
	}

	@Test
	func `records every request in order`() async {
		let sut = CollectingConfirmation(approves: true)

		_ = await sut.confirm(request("myapp://pay/1"))
		_ = await sut.confirm(request("myapp://pay/2"))

		#expect(sut.requests == [request("myapp://pay/1"), request("myapp://pay/2")])
	}

	@Test
	func `decision can change between prompts`() async {
		let sut = CollectingConfirmation(approves: true)
		_ = await sut.confirm(request("myapp://pay"))

		sut.approves = false

		#expect(await sut.confirm(request("myapp://pay")) == false)
	}
}

private func request(_ string: String) -> DeepLinkConfirmationRequest {
	DeepLinkConfirmationRequest(url: URL(string: string)!, context: .unknown)
}
