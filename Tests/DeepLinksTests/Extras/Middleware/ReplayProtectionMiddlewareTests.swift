//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

struct ReplayProtectionMiddlewareTests {
	@Test
	func `first occurrence passes through unchanged`() async throws {
		let (sut, _) = makeSUT()

		#expect(try await sut.intercept(url("myapp://product/1")) == url("myapp://product/1"))
	}

	@Test
	func `identical URL within the window is dropped`() async throws {
		let (sut, clock) = makeSUT(window: 2)
		_ = try await sut.intercept(url("myapp://product/1"))

		clock.advance(by: 1.9)

		#expect(try await sut.intercept(url("myapp://product/1")) == nil)
	}

	@Test
	func `identical URL after the window passes again`() async throws {
		let (sut, clock) = makeSUT(window: 2)
		_ = try await sut.intercept(url("myapp://product/1"))

		clock.advance(by: 2)

		#expect(try await sut.intercept(url("myapp://product/1")) != nil)
	}

	@Test
	func `dropped replays do not extend the window`() async throws {
		let (sut, clock) = makeSUT(window: 2)
		_ = try await sut.intercept(url("myapp://product/1"))

		clock.advance(by: 1.5)
		#expect(try await sut.intercept(url("myapp://product/1")) == nil)

		clock.advance(by: 0.5)
		#expect(try await sut.intercept(url("myapp://product/1")) != nil)
	}

	@Test
	func `different URLs are not deduplicated`() async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url("myapp://product/1"))

		#expect(try await sut.intercept(url("myapp://product/2")) != nil)
	}

	@Test
	func `reject response throws a security violation for a replay`() async throws {
		let (sut, _) = makeSUT(response: .reject)
		_ = try await sut.intercept(url("myapp://product/1"))

		await #expect(throws: DeepLinkError.securityViolation("Replayed deep link")) {
			try await sut.intercept(url("myapp://product/1"))
		}
	}

	@Test
	func `ignored query keys do not distinguish URLs`() async throws {
		let (sut, _) = makeSUT(ignoredQueryKeys: ["utm_source", "ts"])
		_ = try await sut.intercept(url("myapp://product?id=1&utm_source=a&ts=1"))

		#expect(try await sut.intercept(url("myapp://product?id=1&utm_source=b&ts=2")) == nil)
		#expect(try await sut.intercept(url("myapp://product?id=2&utm_source=a&ts=1")) != nil)
	}

	@Test
	func `query parameter order does not distinguish URLs`() async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url("myapp://product?a=1&b=2"))

		#expect(try await sut.intercept(url("myapp://product?b=2&a=1")) == nil)
	}

	@Test
	func `scheme and host case do not distinguish URLs`() async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url("MyApp://Product/1"))

		#expect(try await sut.intercept(url("myapp://product/1")) == nil)
	}

	@Test(arguments: [
		("myapp://x/a%2fb", "myapp://x/a%2Fb"),
		("myapp://x/%41bc", "myapp://x/Abc"),
		("myapp://x/a?q=%7euser", "myapp://x/a?q=~user"),
	])
	func `equivalent percent encodings do not distinguish URLs`(first: String, second: String) async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url(first))

		#expect(try await sut.intercept(url(second)) == nil)
	}

	@Test
	func `malformed escapes are kept literally in the key`() async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url("myapp://x/a%25%2BF"))

		#expect(try await sut.intercept(url("myapp://x/a%25%0F")) != nil)
	}

	@Test
	func `clock moved backwards admits the link instead of extending the window`() async throws {
		let (sut, clock) = makeSUT(window: 2)
		_ = try await sut.intercept(url("myapp://product/1"))

		clock.advance(by: -60)

		#expect(try await sut.intercept(url("myapp://product/1")) != nil)
	}

	@Test
	func `path case distinguishes URLs`() async throws {
		let (sut, _) = makeSUT()
		_ = try await sut.intercept(url("myapp://product/A"))

		#expect(try await sut.intercept(url("myapp://product/a")) != nil)
	}

	@Test
	func `path key ignores query and fragment`() async throws {
		let (sut, _) = makeSUT(key: .path)
		_ = try await sut.intercept(url("myapp://product/1?ref=a#top"))

		#expect(try await sut.intercept(url("myapp://product/1?ref=b")) == nil)
		#expect(try await sut.intercept(url("myapp://product/2?ref=a")) != nil)
	}

	@Test
	func `query parameter key deduplicates by idempotency value`() async throws {
		let (sut, _) = makeSUT(key: .queryParameter("nonce"))
		_ = try await sut.intercept(url("myapp://pay/confirm?nonce=abc"))

		#expect(try await sut.intercept(url("myapp://pay/retry?nonce=abc")) == nil)
		#expect(try await sut.intercept(url("myapp://pay/confirm?nonce=def")) != nil)
	}

	@Test
	func `query parameter key never deduplicates URLs without the parameter`() async throws {
		let (sut, _) = makeSUT(key: .queryParameter("nonce"))
		_ = try await sut.intercept(url("myapp://pay/confirm"))

		#expect(try await sut.intercept(url("myapp://pay/confirm")) != nil)
	}

	@Test
	func `custom key returning nil never deduplicates`() async throws {
		let (sut, _) = makeSUT(key: .custom { _ in nil })
		_ = try await sut.intercept(url("myapp://product/1"))

		#expect(try await sut.intercept(url("myapp://product/1")) != nil)
	}

	@Test
	func `custom key groups URLs by its result`() async throws {
		let (sut, _) = makeSUT(key: .custom { $0.host() })
		_ = try await sut.intercept(url("myapp://product/1"))

		#expect(try await sut.intercept(url("myapp://product/2")) == nil)
	}

	@Test
	func `memory is bounded by evicting the oldest key`() async throws {
		let (sut, _) = makeSUT(maxEntries: 2)
		for path in ["a", "b", "c"] {
			_ = try await sut.intercept(url("myapp://x/\(path)"))
		}

		#expect(try await sut.intercept(url("myapp://x/a")) != nil)
		#expect(try await sut.intercept(url("myapp://x/a")) == nil)
		#expect(sut.trackedKeyCount == 2)
	}

	@Test
	func `expired keys are pruned`() async throws {
		let (sut, clock) = makeSUT(window: 1)
		_ = try await sut.intercept(url("myapp://x/a"))
		_ = try await sut.intercept(url("myapp://x/b"))

		clock.advance(by: 5)
		_ = try await sut.intercept(url("myapp://x/c"))

		#expect(sut.trackedKeyCount == 1)
	}

	@Test(arguments: [0, -1, Double.nan])
	func `non positive window disables protection`(window: TimeInterval) async throws {
		let (sut, _) = makeSUT(window: window)
		_ = try await sut.intercept(url("myapp://product/1"))

		#expect(try await sut.intercept(url("myapp://product/1")) != nil)
	}

	@Test
	func `concurrent identical URLs admit exactly one`() async {
		let (sut, _) = makeSUT()
		let target = url("myapp://product/1")

		let admitted = await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< 20 {
				group.addTask { await (try? sut.intercept(target)) != nil }
			}
			return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
		}

		#expect(admitted == 1)
	}

	@Test
	func `factory builds a configured middleware`() async throws {
		let clock = ManualDateProvider()
		let sut: ReplayProtectionMiddleware = .replayProtection(
			window: 5,
			key: .path,
			response: .reject,
			dateProvider: clock.dateProvider,
		)
		_ = try await sut.intercept(url("myapp://product/1?a=1"))

		await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(url("myapp://product/1?a=2"))
		}
	}

	// MARK: - Helpers

	private func makeSUT(
		window: TimeInterval = 2,
		maxEntries: Int = 100,
		key: ReplayKeyStrategy = .url,
		ignoredQueryKeys: Set<String> = [],
		response: ReplayProtectionMiddleware.Response = .drop,
	) -> (sut: ReplayProtectionMiddleware, clock: ManualDateProvider) {
		let clock = ManualDateProvider()
		let sut = ReplayProtectionMiddleware(
			window: window,
			maxEntries: maxEntries,
			key: key,
			ignoredQueryKeys: ignoredQueryKeys,
			response: response,
			dateProvider: clock.dateProvider,
		)
		return (sut, clock)
	}

	private func url(_ string: String) -> URL {
		URL(string: string)!
	}
}
