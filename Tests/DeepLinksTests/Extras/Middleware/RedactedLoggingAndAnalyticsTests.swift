//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import os
import Testing

struct RedactedLoggingAndAnalyticsTests {
	private static let sensitiveURL = URL(string: "https://example.com/reset?token=abc123&lang=en")!

	@Test(arguments: [
		("singleLine", LoggingFormat.singleLine),
		("json", .json),
		("minimal", .minimal),
		("detailed", .detailed),
	])
	func `redacted logging formats never emit the sensitive value`(name _: String, format: LoggingFormat) async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, format: .redacted(format))

		let result = try await sut.intercept(Self.sensitiveURL)

		#expect(result == Self.sensitiveURL)
		#expect(!messages.all.isEmpty)
		#expect(messages.all.allSatisfy { !$0.contains("abc123") })
		#expect(messages.all.contains { $0.contains("REDACTED") })
	}

	@Test
	func `redacted singleLine keeps the shape of the original format`() async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, format: .redacted(.singleLine))

		_ = try await sut.intercept(Self.sensitiveURL)

		#expect(messages.all == [
			"Deep link intercepted: https://example.com/reset?token=REDACTED&lang=en"
				+ " | scheme=https, host=example.com, path=/reset, params=token=REDACTED&lang=en",
		])
	}

	@Test
	func `redacted logging accepts a custom redactor`() async throws {
		let messages = MessageRecorder()
		let url = try #require(URL(string: "myapp://shop?promo=SUMMER"))
		let sut = LoggingMiddleware(
			loggingProvider: messages.provider,
			format: .redacted(.minimal, using: URLRedactor(sensitiveKeys: ["promo"])),
		)

		_ = try await sut.intercept(url)

		#expect(messages.all == ["Deep link: myapp://shop?promo=REDACTED"])
	}

	@Test(arguments: [
		("singleLine", LoggingFormat.singleLine),
		("json", .json),
		("minimal", .minimal),
		("detailed", .detailed),
	])
	func `built in logging formats redact by default`(name _: String, format: LoggingFormat) async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, format: format)

		_ = try await sut.intercept(Self.sensitiveURL)

		#expect(!messages.all.isEmpty)
		#expect(messages.all.allSatisfy { !$0.contains("abc123") })
	}

	@Test
	func `logging middleware redacts with its default format`() async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider)

		_ = try await sut.intercept(Self.sensitiveURL)

		#expect(messages.all.allSatisfy { !$0.contains("abc123") })
	}

	@Test
	func `unredacted logging format logs the full URL`() async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, format: .unredacted(.minimal))

		_ = try await sut.intercept(Self.sensitiveURL)

		#expect(messages.all == ["Deep link: \(Self.sensitiveURL.absoluteString)"])
	}

	@Test
	func `unredacted undoes an explicit redaction`() async throws {
		let messages = MessageRecorder()
		let sut = LoggingMiddleware(loggingProvider: messages.provider, format: .unredacted(.redacted(.minimal)))

		_ = try await sut.intercept(Self.sensitiveURL)

		#expect(messages.all == ["Deep link: \(Self.sensitiveURL.absoluteString)"])
	}

	@Test
	func `redacted standard analytics redacts the tracked URL`() async throws {
		let provider = AnalyticsProviderSpy()
		let sut = AnalyticsMiddleware(analyticsProvider: provider, strategy: .redacted(.standard))

		_ = try await sut.intercept(Self.sensitiveURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["url"] as? String == "https://example.com/reset?token=REDACTED&lang=en")
	}

	@Test
	func `redacted detailed analytics redacts sensitive query parameters`() async throws {
		let provider = AnalyticsProviderSpy()
		let sut = AnalyticsMiddleware(analyticsProvider: provider, strategy: .redacted(.detailed))

		_ = try await sut.intercept(Self.sensitiveURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["query_parameters"] as? [String: String] == ["token": "REDACTED", "lang": "en"])
	}

	@Test
	func `standard analytics redacts by default`() async throws {
		let provider = AnalyticsProviderSpy()
		let sut = AnalyticsMiddleware(analyticsProvider: provider)

		_ = try await sut.intercept(Self.sensitiveURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["url"] as? String == "https://example.com/reset?token=REDACTED&lang=en")
	}

	@Test
	func `detailed analytics redacts query parameters by default`() async throws {
		let provider = AnalyticsProviderSpy()
		let sut = AnalyticsMiddleware(analyticsProvider: provider, strategy: .detailed)

		_ = try await sut.intercept(Self.sensitiveURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["query_parameters"] as? [String: String] == ["token": "REDACTED", "lang": "en"])
	}

	@Test
	func `unredacted standard analytics tracks the full URL`() async throws {
		let provider = AnalyticsProviderSpy()
		let sut = AnalyticsMiddleware(analyticsProvider: provider, strategy: .unredacted(.standard))

		_ = try await sut.intercept(Self.sensitiveURL)

		let event = try #require(provider.trackedEvents.first)
		#expect(event.parameters["url"] as? String == Self.sensitiveURL.absoluteString)
	}
}
