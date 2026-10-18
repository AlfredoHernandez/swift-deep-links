//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

#if canImport(CryptoKit)

@testable import DeepLinks
import CryptoKit
import DeepLinksTesting
import Foundation
import Testing

struct ReadinessManualDrainTests {
	private let key = SymmetricKey(data: Data(repeating: 5, count: 32))

	@Test
	func `markReady returns the URL the readiness gate received, without its signature parameters`() async throws {
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(queue: queue)
		let link = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/reset?user=42")))

		let unsigned = try #require(URL(string: "https://example.com/reset?user=42"))

		_ = await coordinator.handle(url: link)

		#expect(queue.markReady() == [unsigned])
	}

	@Test
	func `handling a markReady URL again fails the signature check that markReadyAndDrain keeps`() async throws {
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(queue: queue)
		let link = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/reset?user=42")))
		_ = await coordinator.handle(url: link)

		let rehandled = try await coordinator.handle(url: #require(queue.markReady().first))

		#expect(rehandled.firstDeepLinkError == .securityViolation(SignedLinkMiddleware.missingSignatureReason))
	}

	@Test
	func `markReadyAndDrain routes the queued signed link`() async throws {
		let queue = DeepLinkReadinessQueue()
		let coordinator = makeCoordinator(queue: queue)
		let link = try SignedLinkBuilder(key: key).sign(#require(URL(string: "https://example.com/reset?user=42")))
		_ = await coordinator.handle(url: link)

		let drained = await coordinator.markReadyAndDrain(queue: queue)

		#expect(drained.map(\.wasSuccessful) == [true])
	}

	private func makeCoordinator(queue: DeepLinkReadinessQueue) -> DeepLinkCoordinator<TestRoute> {
		DeepLinkCoordinator(
			routing: DefaultDeepLinkRouting(parsers: [ImmediateParser(routes: [TestRoute.route1])]),
			handler: CollectingHandler<TestRoute>(),
			middlewareCoordinator: DeepLinkMiddlewareCoordinator(middleware: [
				SignedLinkMiddleware(keys: SigningKeyring(key: key), requiredFor: .paths(["/reset"]), requiresExpiry: false, maximumLifetime: nil),
				ReadinessMiddleware(queue: queue),
			]),
		)
	}
}

#endif
