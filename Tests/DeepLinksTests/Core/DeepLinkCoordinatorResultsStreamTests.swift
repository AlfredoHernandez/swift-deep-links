//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkCoordinatorResultsStreamTests {
	private let firstURL = URL(string: "myapp://first")!
	private let secondURL = URL(string: "myapp://second")!

	@Test
	func `subscriber receives each handled result in order`() async {
		let sut = makeSUT()
		var iterator = sut.results.makeAsyncIterator()

		await sut.handle(url: firstURL)
		await sut.handle(url: secondURL)

		#expect(await iterator.next()?.originalURL == firstURL)
		#expect(await iterator.next()?.originalURL == secondURL)
	}

	@Test
	func `every subscriber receives the same result`() async {
		let sut = makeSUT()
		var first = sut.results.makeAsyncIterator()
		var second = sut.results.makeAsyncIterator()

		await sut.handle(url: firstURL)

		#expect(await first.next()?.originalURL == firstURL)
		#expect(await second.next()?.originalURL == firstURL)
	}

	@Test
	func `failed and stopped results are published too`() async {
		let routing = DeepLinkRoutingStub<TestRoute>()
		routing.shouldThrowError = true
		let sut = makeSUT(routing: routing)
		var iterator = sut.results.makeAsyncIterator()

		await sut.handle(url: firstURL)

		#expect(await iterator.next()?.hasErrors == true)
	}

	@Test
	func `results handled before subscribing are not replayed`() async {
		let sut = makeSUT()
		await sut.handle(url: firstURL)
		var iterator = sut.results.makeAsyncIterator()

		await sut.handle(url: secondURL)

		#expect(await iterator.next()?.originalURL == secondURL)
	}

	@Test
	func `streams finish when the coordinator is released`() async throws {
		var sut: DeepLinkCoordinator<TestRoute>? = makeSUT()
		let stream = try #require(sut?.results)

		sut = nil

		var received = 0
		for await _ in stream {
			received += 1
		}
		#expect(received == 0)
	}

	@Test
	func `terminated subscribers are removed`() {
		let broadcaster = ResultBroadcaster<TestRoute>()
		var stream: AsyncStream<DeepLinkResult<TestRoute>>? = broadcaster.makeStream()
		#expect(broadcaster.subscriberCount == 1)

		stream = nil

		#expect(stream == nil)
		#expect(broadcaster.subscriberCount == 0)
	}

	// MARK: - Helpers

	private func makeSUT(routing: DeepLinkRoutingStub<TestRoute> = DeepLinkRoutingStub()) -> DeepLinkCoordinator<TestRoute> {
		DeepLinkCoordinator(routing: routing, handler: DeepLinkHandlerSpy())
	}
}
