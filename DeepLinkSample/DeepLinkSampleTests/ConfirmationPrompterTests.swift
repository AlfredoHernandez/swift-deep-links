//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinkSample
import DeepLinks
import Foundation
import Testing

@MainActor
struct ConfirmationPrompterTests {
	private let request = DeepLinkConfirmationRequest(
		url: URL(string: "deeplink://pay?amount=25")!,
		context: DeepLinkContext(source: .customScheme),
	)

	@Test(arguments: [true, false])
	func `Confirm returns the user's answer`(approved: Bool) async {
		let sut = ConfirmationPrompter()

		let answer = Task { await sut.confirm(request) }
		await waitForPrompt(on: sut)
		sut.answer(approved)

		#expect(await answer.value == approved)
		#expect(sut.prompt == nil)
	}

	@Test
	func `Confirm shows the host of the link`() async {
		let sut = ConfirmationPrompter()

		let answer = Task { await sut.confirm(request) }
		await waitForPrompt(on: sut)

		#expect(sut.prompt?.message.contains("pay") == true)
		sut.answer(false)
		_ = await answer.value
	}

	@Test
	func `Cancelling the confirmation denies it and clears the prompt`() async {
		let sut = ConfirmationPrompter()

		let answer = Task { await sut.confirm(request) }
		await waitForPrompt(on: sut)
		answer.cancel()

		#expect(await answer.value == false)
		#expect(sut.prompt == nil)
	}

	@Test
	func `Answering without a prompt does nothing`() {
		let sut = ConfirmationPrompter()

		sut.answer(true)

		#expect(sut.prompt == nil)
	}

	// MARK: - Helpers

	private func waitForPrompt(on sut: ConfirmationPrompter) async {
		for _ in 0 ..< 1000 where sut.prompt == nil {
			await Task.yield()
		}
		if sut.prompt == nil {
			Issue.record("No prompt was shown")
		}
	}
}
