//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(UserNotifications) && !os(tvOS)

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import os
import Testing

struct NotificationDelegatePresenterTests {
	private let sampleURL = URL(string: "myapp://profile")!

	@Test
	@MainActor
	func `error notifications from didFailProcessing are forwarded with failure kind`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: false,
			showErrorNotifications: true,
			showInfoNotifications: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))

		let invocations = await presenter.waitFor(count: 1)
		let invocation = try #require(invocations.first)

		#expect(invocation.kind == .failure)
		#expect(invocation.title == "Deep Link Error")
		#expect(invocation.identifier.hasPrefix("deeplink-critical-error-"))
	}

	@Test
	@MainActor
	func `failed-result notifications from didProcess are forwarded with failure kind`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: false,
			showErrorNotifications: true,
			showInfoNotifications: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()
		let failingResult = DeepLinkResult<TestRoute>(
			originalURL: sampleURL,
			processedURL: sampleURL,
			routes: [.route1],
			executionTime: 0,
			errors: [DeepLinkError.handlerError(message: "boom", underlyingError: nil)],
			successfulRoutes: 0,
			failedRoutes: 1,
		)

		delegate.coordinator(coordinator, didProcess: sampleURL, result: failingResult)

		let invocations = await presenter.waitFor(count: 1)
		let invocation = try #require(invocations.first)

		#expect(invocation.kind == .failure)
		#expect(invocation.title == "Deep Link Failed")
		#expect(invocation.identifier.hasPrefix("deeplink-error-"))
	}

	@Test
	@MainActor
	func `success notifications are forwarded with success kind when showSuccessNotifications is true`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: true,
			showErrorNotifications: false,
			showInfoNotifications: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()
		let successfulResult = DeepLinkResult<TestRoute>(
			originalURL: sampleURL,
			processedURL: sampleURL,
			routes: [.route1],
			executionTime: 0,
			errors: [],
			successfulRoutes: 1,
			failedRoutes: 0,
		)

		delegate.coordinator(coordinator, didProcess: sampleURL, result: successfulResult)

		let invocations = await presenter.waitFor(count: 1)
		let invocation = try #require(invocations.first)

		#expect(invocation.kind == .success)
		#expect(invocation.title == "Deep Link Opened")
		#expect(invocation.identifier.hasPrefix("deeplink-success-"))
	}

	@Test
	@MainActor
	func `info notifications are forwarded with info kind when showInfoNotifications is true`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: false,
			showErrorNotifications: false,
			showInfoNotifications: true,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, willProcess: sampleURL)

		let invocations = await presenter.waitFor(count: 1)
		let invocation = try #require(invocations.first)

		#expect(invocation.kind == .info)
		#expect(invocation.title == "Deep Link Processing")
		#expect(invocation.identifier.hasPrefix("deeplink-processing-"))
	}

	@Test
	@MainActor
	func `success notifications are suppressed when showSuccessNotifications is false`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: false,
			showErrorNotifications: true,
			showInfoNotifications: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()
		let successfulResult = DeepLinkResult<TestRoute>(
			originalURL: sampleURL,
			processedURL: sampleURL,
			routes: [.route1],
			executionTime: 0,
			errors: [],
			successfulRoutes: 1,
			failedRoutes: 0,
		)

		delegate.coordinator(coordinator, didProcess: sampleURL, result: successfulResult)

		// Let any stray task drain; no presenter call is expected.
		await Task.yield()
		await Task.yield()

		let invocations = await presenter.recordedInvocations
		#expect(invocations.isEmpty)
	}

	@Test
	@MainActor
	func `deinit cancels pending notification tasks before they reach the presenter`() async throws {
		let presenter = RecordingPresenter()
		let coordinator = try makeCoordinator()

		// Scope delegate to a child block so its sole strong reference drops
		// deterministically before we yield MainActor.
		do {
			var delegate: DeepLinkNotificationDelegate<TestRoute>? = DeepLinkNotificationDelegate<TestRoute>(
				showSuccessNotifications: false,
				showErrorNotifications: true,
				showInfoNotifications: false,
				presenter: presenter,
			)
			// Schedule a task; body hasn't run yet — MainActor is still inside
			// this function synchronously, so the Task literal is constructed
			// but the body is not yet dispatched.
			delegate?.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))
			// Drop the last strong reference within the same MainActor frame.
			// deinit cancels the pending task before its body ever unwraps `self`.
			delegate = nil
		}

		// Yield so any queued MainActor work drains. The cancelled task body
		// unwraps `[weak self]` to nil, returns immediately, and never touches
		// the presenter. Bounded yield loop in place of a wall-clock sleep so
		// the fence is deterministic under CI load.
		for _ in 0 ..< 10 {
			await Task.yield()
		}

		let entered = await presenter.wasEntered
		#expect(entered == false)
	}

	@Test
	@MainActor
	func `presenter errors are swallowed so subsequent lifecycle events still schedule`() async throws {
		let presenter = FailingPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(
			showSuccessNotifications: false,
			showErrorNotifications: true,
			showInfoNotifications: false,
			presenter: presenter,
		)
		let coordinator = try makeCoordinator()

		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))
		delegate.coordinator(coordinator, didFailProcessing: sampleURL, error: DeepLinkError.unsupportedScheme("ftp"))

		let count = await presenter.waitFor(count: 2)
		#expect(count == 2)
	}

	// MARK: - Helpers

	private func makeCoordinator() throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.build()
	}
}

// MARK: - Test Doubles

/// Records whether `present(...)` has been entered. Used by the deinit-
/// cancellation regression test to assert that a task queued before the
/// delegate is released never reaches the presenter.
private actor RecordingPresenter: DeepLinkNotificationPresenter {
	private var enteredCount = 0

	var wasEntered: Bool {
		enteredCount > 0
	}

	func present(kind _: DeepLinkNotificationKind, title _: String, body _: String, identifier _: String) async throws {
		enteredCount += 1
	}
}

private actor FailingPresenter: DeepLinkNotificationPresenter {
	private var count = 0
	private var pendingAwaiter: (count: Int, continuation: CheckedContinuation<Int, Never>)?

	func present(kind _: DeepLinkNotificationKind, title _: String, body _: String, identifier _: String) async throws {
		count += 1
		if let awaiter = pendingAwaiter, count >= awaiter.count {
			let snapshot = count
			pendingAwaiter = nil
			awaiter.continuation.resume(returning: snapshot)
		}
		throw NSError(domain: "test", code: 1)
	}

	func waitFor(count: Int) async -> Int {
		if self.count >= count {
			return self.count
		}
		return await withCheckedContinuation { continuation in
			pendingAwaiter = (count, continuation)
		}
	}
}

#endif
