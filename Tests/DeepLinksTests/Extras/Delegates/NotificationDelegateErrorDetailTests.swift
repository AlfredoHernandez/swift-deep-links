//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

#if canImport(UserNotifications) && !os(tvOS)

@testable import DeepLinks
import DeepLinksTesting
import Foundation
import Testing

@MainActor
struct NotificationDelegateErrorDetailTests {
	private static let sensitiveURL = URL(string: "https://example.com/reset?token=abc123")!
	private static let error = DeepLinkError.routeNotFound(sensitiveURL)

	@Test
	func `full detail keeps the existing message`() async throws {
		let body = try await failureBody(errorDetail: .full)

		#expect(body == "Failed to process link: \(Self.error.localizedDescription)")
	}

	@Test
	func `default detail is redacted`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(presenter: presenter)

		try delegate.coordinator(makeCoordinator(), didFailProcessing: Self.sensitiveURL, error: Self.error)

		let invocation = try #require(await presenter.waitFor(count: 1).first)
		#expect(!invocation.body.contains("abc123"))
		#expect(invocation.body.contains("REDACTED"))
	}

	@Test
	func `redacted detail hides sensitive URL values`() async throws {
		let body = try await failureBody(errorDetail: .redacted)

		#expect(body == "Failed to process link: No route found for URL: https://example.com/reset?token=REDACTED")
	}

	@Test
	func `redacted detail does not reveal text of foreign errors`() async throws {
		let body = try await failureBody(errorDetail: .redacted, error: ForeignError())

		#expect(body == "Failed to process link: ForeignError")
	}

	@Test
	func `generic detail shows no error text`() async throws {
		let body = try await failureBody(errorDetail: .generic)

		#expect(body == "Failed to process link")
	}

	@Test
	func `failed result uses the configured detail`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(presenter: presenter, errorDetail: .redacted)
		let result = DeepLinkResult<TestRoute>(
			originalURL: Self.sensitiveURL,
			processedURL: Self.sensitiveURL,
			routes: [],
			executionTime: 0,
			errors: [Self.error],
			successfulRoutes: 0,
			failedRoutes: 0,
		)

		try delegate.coordinator(makeCoordinator(), didProcess: Self.sensitiveURL, result: result)

		let invocation = try #require(await presenter.waitFor(count: 1).first)
		#expect(invocation.body == "Could not open link: No route found for URL: https://example.com/reset?token=REDACTED")
	}

	@Test
	func `notification factory forwards the error detail`() async throws {
		let presenter = CollectingNotificationPresenter()
		let delegate: DeepLinkNotificationDelegate<TestRoute> = .notification(presenter: presenter, errorDetail: .generic)

		try delegate.coordinator(makeCoordinator(), didFailProcessing: Self.sensitiveURL, error: Self.error)

		let invocation = try #require(await presenter.waitFor(count: 1).first)
		#expect(invocation.body == "Failed to process link")
	}

	private func failureBody(
		errorDetail: DeepLinkNotificationErrorDetail,
		error: any Error = Self.error,
	) async throws -> String {
		let presenter = CollectingNotificationPresenter()
		let delegate = DeepLinkNotificationDelegate<TestRoute>(presenter: presenter, errorDetail: errorDetail)

		try delegate.coordinator(makeCoordinator(), didFailProcessing: Self.sensitiveURL, error: error)

		return try #require(await presenter.waitFor(count: 1).first).body
	}

	private func makeCoordinator() throws -> DeepLinkCoordinator<TestRoute> {
		try DeepLinkCoordinatorBuilder<TestRoute>()
			.routing(DeepLinkRoutingStub<TestRoute>())
			.handler(DeepLinkHandlerSpy<TestRoute>())
			.build()
	}
}

private struct ForeignError: LocalizedError {
	var errorDescription: String? {
		"secret user@example.com leaked"
	}
}

#endif
