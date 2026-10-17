//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct ConfirmingHandlerLimitsTests {
	@Test(.timeLimit(.minutes(1)))
	func `an unanswered prompt times out after sixty seconds by default`() async {
		let requested = OSAllocatedUnfairLock<[Duration]>(initialState: [])
		let inner = CollectingHandler<TestRoute>()
		let sut = ConfirmingHandler(inner, requiredFor: .all, sleep: { duration in requested.withLock { $0.append(duration) } }) { _, _ in
			await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in }
		}

		await #expect(throws: DeepLinkError.self) {
			try await sut.handle(.route1, context: .unknown)
		}
		#expect(requested.withLock { $0 } == [.seconds(60)])
		#expect(inner.handledRoutes.isEmpty)
	}

	@Test(.timeLimit(.minutes(1)))
	func `the decorating factory also times out after sixty seconds by default`() async {
		let inner = CollectingHandler<TestRoute>()
		let sut = inner.confirming(.all) { _, _ in true }

		try? await sut.handle(.route1, context: .unknown)

		#expect(inner.handledRoutes == [.route1])
		#expect(ConfirmingHandler<TestRoute>.defaultTimeout == ConfirmationMiddleware.defaultTimeout)
		#expect(ConfirmingHandler<TestRoute>.defaultMaxPendingPrompts == ConfirmationMiddleware.defaultMaxPendingPrompts)
	}

	@Test(.timeLimit(.minutes(1)))
	func `twenty concurrent links prompt at most two at a time and reject the rest without a prompt`() async throws {
		let answers = AnswerLatch()
		let inner = CollectingHandler<TestRoute>()
		let sut = ConfirmingHandler(inner, requiredFor: .all, sleep: neverElapses) { _, _ in
			await answers.wait()
		}
		let (outcomes, outcome) = AsyncStream<Result<Void, any Error>>.makeStream()

		for _ in 0 ..< 20 {
			Task {
				do {
					try await sut.handle(.route1, context: .unknown)
					outcome.yield(.success(()))
				} catch {
					outcome.yield(.failure(error))
				}
			}
		}
		var iterator = outcomes.makeAsyncIterator()
		var rejections: [DeepLinkError] = []
		for _ in 0 ..< 18 {
			let result = try #require(await iterator.next())
			if case let .failure(error as DeepLinkError) = result {
				rejections.append(error)
			}
		}
		answers.open()
		let approved = try await [#require(iterator.next()), #require(iterator.next())]

		#expect(rejections == Array(repeating: .securityViolation(ConfirmationMiddleware.tooManyPendingPromptsReason), count: 18))
		#expect(approved.allSatisfy { (try? $0.get()) != nil })
		#expect(answers.askedCount == 2)
		#expect(inner.handledRoutes == [.route1, .route1])
	}

	@Test(.timeLimit(.minutes(1)))
	func `prompts are shown one at a time`() async throws {
		let answers = AnswerLatch()
		let sut = ConfirmingHandler(CollectingHandler<TestRoute>(), requiredFor: .all, sleep: neverElapses) { _, _ in
			await answers.wait()
		}

		let first = Task { try await sut.handle(.route1, context: .unknown) }
		await answers.firstAsk()
		let second = Task { try await sut.handle(.route2, context: .unknown) }
		await Task.yield()

		#expect(answers.askedCount == 1)
		answers.open()
		try await first.value
		try await second.value
		#expect(answers.askedCount == 2)
	}

	@Test(arguments: [(0, 1), (-3, 1), (5, 5)])
	func `the pending limit is at least one`(requested: Int, effective: Int) {
		let sut = ConfirmingHandler(CollectingHandler<TestRoute>(), requiredFor: .all, maxPendingPrompts: requested) { _, _ in true }

		#expect(sut.maxPendingPrompts == effective)
	}
}

// MARK: - Helpers

private let neverElapses: @Sendable (Duration) async throws -> Void = { _ in
	let (stream, _) = AsyncStream<Void>.makeStream()
	for await _ in stream {}
}

/// Holds every prompt until ``open()``, then approves current and later prompts.
private final class AnswerLatch: Sendable {
	private struct State {
		var isOpen = false
		var asked = 0
		var waiting: [CheckedContinuation<Bool, Never>] = []
		var askWatchers: [CheckedContinuation<Void, Never>] = []
	}

	private let state = OSAllocatedUnfairLock(initialState: State())

	var askedCount: Int {
		state.withLock { $0.asked }
	}

	func wait() async -> Bool {
		await withCheckedContinuation { continuation in
			let (resumeNow, watchers) = state.withLock { state -> (Bool, [CheckedContinuation<Void, Never>]) in
				state.asked += 1
				defer { state.askWatchers = [] }
				if state.isOpen {
					return (true, state.askWatchers)
				}
				state.waiting.append(continuation)
				return (false, state.askWatchers)
			}
			watchers.forEach { $0.resume() }
			if resumeNow {
				continuation.resume(returning: true)
			}
		}
	}

	func firstAsk() async {
		await withCheckedContinuation { continuation in
			let isAsked = state.withLock { state in
				guard state.asked == 0 else { return true }
				state.askWatchers.append(continuation)
				return false
			}
			if isAsked {
				continuation.resume()
			}
		}
	}

	func open() {
		let waiting = state.withLock { state in
			state.isOpen = true
			defer { state.waiting = [] }
			return state.waiting
		}
		waiting.forEach { $0.resume(returning: true) }
	}
}
