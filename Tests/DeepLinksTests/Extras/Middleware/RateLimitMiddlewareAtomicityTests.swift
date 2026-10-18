//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import os
import Testing

struct RateLimitMiddlewareAtomicityTests {
	private let url = URL(string: "testapp://test")!
	private let now = Date(timeIntervalSince1970: 1_700_000_000)

	@Test(arguments: [RateLimitStrategyCase.slidingWindow, .fixedWindow])
	func `concurrent intercepts allow exactly the configured number of requests`(strategy: RateLimitStrategyCase) async {
		let persistence = InterleavingRateLimitPersistence()
		let sut = RateLimitMiddleware(
			maxRequests: 5,
			timeWindow: 60,
			persistence: persistence,
			strategy: strategy.value,
			dateProvider: { [now] in now },
		)

		let allowed = await countAllowed(concurrentRequests: 50, through: sut)

		#expect(allowed == 5)
		#expect(await persistence.loadRequests().count == 5)
	}

	@Test(arguments: [RateLimitStrategyCase.slidingWindow, .fixedWindow, .tokenBucket])
	func `separate instances sharing a persistence allow exactly the configured number of requests`(
		strategy: RateLimitStrategyCase,
	) async {
		let persistence = InterleavingRateLimitPersistence()
		let instances = (0 ..< 5).map { _ in
			RateLimitMiddleware(
				maxRequests: 5,
				timeWindow: 60,
				persistence: persistence,
				strategy: strategy.value,
				dateProvider: { [now] in now },
			)
		}

		let allowed = await withTaskGroup(of: Bool.self) { group in
			for index in 0 ..< 50 {
				group.addTask { [url] in
					await (try? instances[index % instances.count].intercept(url: url)) != nil
				}
			}
			return await group.reduce(0) { $1 ? $0 + 1 : $0 }
		}

		#expect(allowed == 5)
	}

	@Test
	func `a cancelled request does not consume rate-limit budget`() async throws {
		let persistence = InMemoryRateLimitPersistence()
		let sut = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: 60,
			persistence: persistence,
			dateProvider: { [now] in now },
		)

		let cancelledRequest = Task { [url] in
			withUnsafeCurrentTask { $0?.cancel() }
			return try await sut.intercept(url: url)
		}

		await #expect(throws: CancellationError.self) {
			try await cancelledRequest.value
		}
		#expect(await persistence.loadRequests().isEmpty)
		#expect(try await sut.intercept(url: url) == url)
	}

	@Test(arguments: [0.0, -10.0])
	func `fixed window with a non-positive time window still limits requests`(timeWindow: TimeInterval) async throws {
		let sut = makeSUT(maxRequests: 1, timeWindow: timeWindow, strategy: .fixedWindow)

		_ = try await sut.intercept(url: url)

		await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(url: url)
		}
	}

	@Test
	func `fixed window with a zero time window admits requests again at a later instant`() async throws {
		let clock = SteppingDateProvider(start: now, step: 1)
		let sut = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: 0,
			persistence: InMemoryRateLimitPersistence(),
			strategy: .fixedWindow,
			dateProvider: clock.next,
		)

		_ = try await sut.intercept(url: url)
		let laterResult = try await sut.intercept(url: url)

		#expect(laterResult == url)
	}

	@Test
	func `fixed window with an infinite time window limits requests far apart in time`() async throws {
		let clock = SteppingDateProvider(start: now, step: 1_000_000)
		let sut = RateLimitMiddleware(
			maxRequests: 1,
			timeWindow: .infinity,
			persistence: InMemoryRateLimitPersistence(),
			strategy: .fixedWindow,
			dateProvider: clock.next,
		)

		_ = try await sut.intercept(url: url)

		await #expect(throws: DeepLinkError.self) {
			try await sut.intercept(url: url)
		}
	}

	@Test(arguments: [RateLimitStrategyCase.slidingWindow, .fixedWindow])
	func `a NaN time window is treated as zero and still limits requests`(strategy: RateLimitStrategyCase) async throws {
		let sut = makeSUT(maxRequests: 1, timeWindow: .nan, strategy: strategy.value)

		_ = try await sut.intercept(url: url)

		await #expect(throws: DeepLinkError.rateLimitExceeded(maxRequests: 1, timeWindow: 0)) {
			try await sut.intercept(url: url)
		}
	}

	private func makeSUT(maxRequests: Int, timeWindow: TimeInterval, strategy: RateLimitStrategy) -> RateLimitMiddleware {
		RateLimitMiddleware(
			maxRequests: maxRequests,
			timeWindow: timeWindow,
			persistence: InMemoryRateLimitPersistence(),
			strategy: strategy,
			dateProvider: { [now] in now },
		)
	}

	private func countAllowed(concurrentRequests: Int, through sut: RateLimitMiddleware) async -> Int {
		await withTaskGroup(of: Bool.self) { group in
			for _ in 0 ..< concurrentRequests {
				group.addTask { [url] in
					await (try? sut.intercept(url: url)) != nil
				}
			}
			return await group.reduce(0) { $1 ? $0 + 1 : $0 }
		}
	}
}

// MARK: - Test Doubles

enum RateLimitStrategyCase: String, CustomTestStringConvertible, Sendable {
	case slidingWindow
	case fixedWindow
	case tokenBucket

	var value: RateLimitStrategy {
		switch self {
		case .slidingWindow:
			.slidingWindow

		case .fixedWindow:
			.fixedWindow

		case .tokenBucket:
			.tokenBucket(capacity: 5, refillRate: 0.001)
		}
	}

	var testDescription: String {
		rawValue
	}
}

/// Yields inside every load and save so concurrent callers interleave across
/// the suspension points the way a real actor-backed store allows.
private actor InterleavingRateLimitPersistence: RateLimitPersistence {
	private var timestamps: [TimeInterval] = []

	func loadRequests() async -> [TimeInterval] {
		await Task.yield()
		return timestamps
	}

	func saveRequests(_ timestamps: [TimeInterval]) async {
		await Task.yield()
		self.timestamps = timestamps
	}

	func clearRequests() {
		timestamps.removeAll()
	}

	func mutateRequests<Output: Sendable>(_ mutation: @Sendable (inout [TimeInterval]) -> Output) -> Output {
		mutation(&timestamps)
	}
}

/// Returns a later instant on every call, `step` seconds apart.
private final class SteppingDateProvider: Sendable {
	private let current: OSAllocatedUnfairLock<Date>
	private let step: TimeInterval

	init(start: Date, step: TimeInterval) {
		current = OSAllocatedUnfairLock(initialState: start)
		self.step = step
	}

	var next: @Sendable () -> Date {
		{ [current, step] in
			current.withLock { date in
				defer { date = date.addingTimeInterval(step) }
				return date
			}
		}
	}
}
