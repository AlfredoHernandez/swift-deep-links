//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct ConfirmationMiddlewareTests {
	// MARK: - Decisions

	@Test
	func `approved link continues unchanged`() async throws {
		let sut = ConfirmationMiddleware(provider: CollectingConfirmation(approves: true))
		let request = DeepLinkRequest(url: url("myapp://pay?amount=10&token=secret"), context: DeepLinkContext(source: .universalLink))

		#expect(try await sut.intercept(request) == request)
	}

	@Test
	func `denied link throws confirmationDenied with the original URL`() async throws {
		let sut = ConfirmationMiddleware(provider: CollectingConfirmation(approves: false))

		await #expect(throws: DeepLinkError.confirmationDenied(url("myapp://pay?token=secret"))) {
			try await sut.intercept(DeepLinkRequest(url: url("myapp://pay?token=secret")))
		}
	}

	@Test
	func `links outside the matcher are not confirmed`() async throws {
		let provider = CollectingConfirmation(approves: false)
		let sut = ConfirmationMiddleware(provider: provider, requiredFor: .hosts(["pay"]))
		let request = DeepLinkRequest(url: url("myapp://home"))

		#expect(try await sut.intercept(request) == request)
		#expect(provider.requests.isEmpty)
	}

	@Test
	func `provider receives the redacted URL and the context`() async throws {
		let provider = CollectingConfirmation(approves: true)
		let sut = ConfirmationMiddleware(provider: provider)
		let context = DeepLinkContext(source: .customScheme, sourceApplication: "com.other", sceneID: "scene-1")

		_ = try await sut.intercept(DeepLinkRequest(url: url("myapp://pay?amount=10&token=secret"), context: context))

		#expect(provider.requests == [
			DeepLinkConfirmationRequest(url: url("myapp://pay?amount=10&token=REDACTED"), context: context),
		])
	}

	@Test
	func `custom redactor is applied to the prompt URL`() async throws {
		let provider = CollectingConfirmation(approves: true)
		let sut = ConfirmationMiddleware(provider: provider, redactor: URLRedactor(sensitiveKeys: ["amount"], placeholder: "***"))

		_ = try await sut.intercept(DeepLinkRequest(url: url("myapp://pay?amount=10")))

		#expect(provider.requests.map(\.url) == [url("myapp://pay?amount=***")])
	}

	// MARK: - Timeout

	@Test(.timeLimit(.minutes(1)))
	func `unanswered prompt times out as a denial and is cancelled`() async throws {
		let provider = GatedConfirmation()
		let sleeps = SleepRecorder()
		let sut = ConfirmationMiddleware(provider: provider, timeout: .seconds(30), sleep: sleeps.returnImmediately)

		await #expect(throws: DeepLinkError.confirmationDenied(url("myapp://pay"))) {
			try await sut.intercept(DeepLinkRequest(url: url("myapp://pay")))
		}
		#expect(sleeps.durations == [.seconds(30)])
		var cancellations = provider.cancellations.makeAsyncIterator()
		_ = await cancellations.next()
	}

	@Test(.timeLimit(.minutes(1)))
	func `timeout denies and frees the next prompt even when the provider ignores cancellation`() async throws {
		let provider = StubbornConfirmation()
		let sut = ConfirmationMiddleware(provider: provider, timeout: .seconds(30), sleep: SleepRecorder().returnImmediately)

		await #expect(throws: DeepLinkError.confirmationDenied(url("myapp://pay/1"))) {
			try await sut.intercept(DeepLinkRequest(url: url("myapp://pay/1")))
		}
		await #expect(throws: DeepLinkError.confirmationDenied(url("myapp://pay/2"))) {
			try await sut.intercept(DeepLinkRequest(url: url("myapp://pay/2")))
		}

		#expect(provider.askedCount == 2)
		provider.answerAll(true)
	}

	@Test(.timeLimit(.minutes(1)))
	func `cancelling the link denies it even when the provider ignores cancellation`() async throws {
		let provider = StubbornConfirmation()
		let sut = ConfirmationMiddleware(provider: provider, timeout: .seconds(30), sleep: SleepRecorder().suspendUntilCancelled)
		var prompts = provider.prompts.makeAsyncIterator()

		let link = Task { try await sut.intercept(DeepLinkRequest(url: url("myapp://pay"))) }
		_ = await prompts.next()
		link.cancel()

		await #expect(throws: DeepLinkError.confirmationDenied(url("myapp://pay"))) { try await link.value }
		provider.answerAll(true)
	}

	@Test(.timeLimit(.minutes(1)))
	func `answer before the timeout wins and cancels the timer`() async throws {
		let sleeps = SleepRecorder()
		let sut = ConfirmationMiddleware(
			provider: CollectingConfirmation(approves: true),
			timeout: .seconds(30),
			sleep: sleeps.suspendUntilCancelled,
		)

		#expect(try await sut.intercept(DeepLinkRequest(url: url("myapp://pay"))) != nil)
		var cancellations = sleeps.cancellations.makeAsyncIterator()
		_ = await cancellations.next()
	}

	@Test
	func `no timeout never starts a timer`() async throws {
		let sleeps = SleepRecorder()
		let sut = ConfirmationMiddleware(provider: CollectingConfirmation(approves: true), sleep: sleeps.returnImmediately)

		_ = try await sut.intercept(DeepLinkRequest(url: url("myapp://pay")))

		#expect(sleeps.durations.isEmpty)
	}

	// MARK: - Serialization

	@Test
	func `prompts are shown one at a time and a link cancelled while waiting is never shown`() async throws {
		let provider = GatedConfirmation()
		let sut = ConfirmationMiddleware(provider: provider)
		var prompts = provider.prompts.makeAsyncIterator()

		let first = Task { try await sut.intercept(DeepLinkRequest(url: url("myapp://pay/1"))) }
		_ = await prompts.next()
		let second = Task { try await sut.intercept(DeepLinkRequest(url: url("myapp://pay/2"))) }
		second.cancel()
		provider.answerAll(true)

		#expect(try await first.value != nil)
		await #expect(throws: CancellationError.self) { try await second.value }
		#expect(provider.askedCount == 1)
	}

	// MARK: - Coordinator

	@Test
	func `denied link fails processing without reaching the handler`() async throws {
		let handler = CollectingHandler<TestRoute>()
		let coordinator = try DeepLinkCoordinatorBuilder<TestRoute>()
			.parser(ImmediateParser(routes: [.route1]))
			.handler(handler)
			.middleware(.confirmation(provider: CollectingConfirmation(approves: false)))
			.build()

		let result = await coordinator.handle(url: url("myapp://pay"))

		#expect(result.firstDeepLinkError == .confirmationDenied(url("myapp://pay")))
		#expect(handler.handledRoutes.isEmpty)
	}
}

// MARK: - Helpers

private func url(_ string: String) -> URL {
	URL(string: string)!
}

/// Answers only when the test calls ``answerAll(_:)``; a cancelled prompt answers `false`.
private final class GatedConfirmation: DeepLinkConfirmationProvider {
	private struct State {
		var waiting: [UUID: CheckedContinuation<Bool, Never>] = [:]
		var asked = 0
	}

	private let state = OSAllocatedUnfairLock(initialState: State())
	private let cancellationEvents = AsyncStream<Void>.makeStream()
	private let promptContinuation: AsyncStream<DeepLinkConfirmationRequest>.Continuation
	let prompts: AsyncStream<DeepLinkConfirmationRequest>

	init() {
		(prompts, promptContinuation) = AsyncStream.makeStream()
	}

	var askedCount: Int {
		state.withLock { $0.asked }
	}

	/// Yields once per cancelled prompt, whenever the cancellation lands.
	var cancellations: AsyncStream<Void> {
		cancellationEvents.stream
	}

	func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
		let id = UUID()
		state.withLock { $0.asked += 1 }
		return await withTaskCancellationHandler {
			await withCheckedContinuation { continuation in
				let isCancelled = state.withLock { state in
					guard !Task.isCancelled else { return true }
					state.waiting[id] = continuation
					return false
				}
				if isCancelled {
					continuation.resume(returning: false)
				}
				promptContinuation.yield(request)
			}
		} onCancel: {
			let continuation = state.withLock { state in
				state.waiting.removeValue(forKey: id)
			}
			cancellationEvents.continuation.yield()
			continuation?.resume(returning: false)
		}
	}

	func answerAll(_ decision: Bool) {
		let continuations = state.withLock { state in
			defer { state.waiting.removeAll() }
			return Array(state.waiting.values)
		}
		continuations.forEach { $0.resume(returning: decision) }
	}
}

/// Never reacts to cancellation; answers only when the test calls ``answerAll(_:)``.
private final class StubbornConfirmation: DeepLinkConfirmationProvider {
	private struct State {
		var waiting: [CheckedContinuation<Bool, Never>] = []
		var asked = 0
	}

	private let state = OSAllocatedUnfairLock(initialState: State())
	private let promptContinuation: AsyncStream<DeepLinkConfirmationRequest>.Continuation
	let prompts: AsyncStream<DeepLinkConfirmationRequest>

	init() {
		(prompts, promptContinuation) = AsyncStream.makeStream()
	}

	var askedCount: Int {
		state.withLock { $0.asked }
	}

	func confirm(_ request: DeepLinkConfirmationRequest) async -> Bool {
		await withCheckedContinuation { continuation in
			state.withLock { state in
				state.asked += 1
				state.waiting.append(continuation)
			}
			promptContinuation.yield(request)
		}
	}

	func answerAll(_ decision: Bool) {
		let continuations = state.withLock { state in
			defer { state.waiting.removeAll() }
			return state.waiting
		}
		continuations.forEach { $0.resume(returning: decision) }
	}
}

private final class SleepRecorder: Sendable {
	private struct State {
		var durations: [Duration] = []
		var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]
	}

	private let state = OSAllocatedUnfairLock(initialState: State())
	private let cancellationEvents = AsyncStream<Void>.makeStream()

	var durations: [Duration] {
		state.withLock { $0.durations }
	}

	/// Yields once per cancelled sleep, whenever the cancellation lands.
	var cancellations: AsyncStream<Void> {
		cancellationEvents.stream
	}

	var returnImmediately: @Sendable (Duration) async throws -> Void {
		{ [state] duration in state.withLock { $0.durations.append(duration) } }
	}

	var suspendUntilCancelled: @Sendable (Duration) async throws -> Void {
		{ [state, cancellationEvents] duration in
			let id = UUID()
			state.withLock { $0.durations.append(duration) }
			await withTaskCancellationHandler {
				await withCheckedContinuation { continuation in
					let isCancelled = state.withLock { state in
						guard !Task.isCancelled else { return true }
						state.waiting[id] = continuation
						return false
					}
					if isCancelled {
						continuation.resume()
					}
				}
			} onCancel: {
				let continuation = state.withLock { state in
					state.waiting.removeValue(forKey: id)
				}
				cancellationEvents.continuation.yield()
				continuation?.resume()
			}
			throw CancellationError()
		}
	}
}
