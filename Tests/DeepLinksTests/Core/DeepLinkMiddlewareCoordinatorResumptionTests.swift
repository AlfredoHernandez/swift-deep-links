//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct DeepLinkMiddlewareCoordinatorResumptionTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `process starting after an anchor runs only the middleware that follows it`() async throws {
		let before = CollectingMiddleware()
		let anchor = CollectingMiddleware()
		let after = CollectingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [before, anchor, after])

		let result = try await sut.process(url, startingAfter: anchor)

		#expect(result == url)
		#expect(before.interceptedURLs.isEmpty)
		#expect(anchor.interceptedURLs.isEmpty)
		#expect(after.interceptedURLs == [url])
	}

	@Test
	func `process starting after the last middleware returns the URL unchanged`() async throws {
		let only = CollectingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [only])

		let result = try await sut.process(url, startingAfter: only)

		#expect(result == url)
		#expect(only.interceptedURLs.isEmpty)
	}

	@Test
	func `process starting after an unregistered anchor runs the whole chain`() async throws {
		let registered = CollectingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [registered])

		let result = try await sut.process(url, startingAfter: CollectingMiddleware())

		#expect(result == url)
		#expect(registered.interceptedURLs == [url])
	}

	@Test
	func `process starting after an anchor stops when a following middleware returns nil`() async throws {
		let anchor = CollectingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [anchor, StoppingMiddleware()])

		let result = try await sut.process(url, startingAfter: anchor)

		#expect(result == nil)
	}
}
