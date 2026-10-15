//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import os
import Testing

struct MiddlewareIntervalTracingTests {
	private let url = URL(string: "myapp://home")!

	@Test
	func `each middleware runs inside its own interval in chain order`() async throws {
		let tracing = RecordingIntervalTracing()
		let sut = DeepLinkMiddlewareCoordinator(
			middleware: [PassingMiddleware(), StoppingMiddleware()],
			tracing: tracing,
		)

		_ = try await sut.process(url: url)

		#expect(tracing.events == [
			"begin PassingMiddleware",
			"end PassingMiddleware",
			"begin StoppingMiddleware",
			"end StoppingMiddleware",
		])
	}

	@Test
	func `interval ends when a middleware throws`() async {
		let tracing = RecordingIntervalTracing()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [ThrowingMiddleware(), PassingMiddleware()], tracing: tracing)

		await #expect(throws: DeepLinkError.self) { try await sut.process(url: url) }

		#expect(tracing.events == ["begin ThrowingMiddleware", "end ThrowingMiddleware"])
	}

	@Test
	func `resumed chains trace only the middleware that runs`() async throws {
		let tracing = RecordingIntervalTracing()
		let anchor = PassingMiddleware()
		let sut = DeepLinkMiddlewareCoordinator(middleware: [anchor, StoppingMiddleware()], tracing: tracing)

		_ = try await sut.process(url: url, startingAfter: anchor)

		#expect(tracing.events == ["begin StoppingMiddleware", "end StoppingMiddleware"])
	}

	@Test
	func `tracing does not change the processed URL`() async throws {
		let traced = DeepLinkMiddlewareCoordinator(middleware: [PassingMiddleware()], tracing: RecordingIntervalTracing())
		let plain = DeepLinkMiddlewareCoordinator(middleware: [PassingMiddleware()])

		#expect(try await traced.process(url: url) == plain.process(url: url))
	}
}

// MARK: - Test Doubles

private final class RecordingIntervalTracing: MiddlewareIntervalTracing {
	private let recorded = OSAllocatedUnfairLock<[String]>(initialState: [])

	var events: [String] {
		recorded.withLock { $0 }
	}

	func beginInterval(named name: String) -> any MiddlewareInterval {
		recorded.withLock { $0.append("begin \(name)") }
		return RecordingInterval { [recorded] in recorded.withLock { $0.append("end \(name)") } }
	}
}

private struct RecordingInterval: MiddlewareInterval {
	let onEnd: @Sendable () -> Void

	func end() {
		onEnd()
	}
}

private final class PassingMiddleware: DeepLinkMiddleware {
	func intercept(_ request: DeepLinkRequest) async throws -> DeepLinkRequest? {
		request
	}
}

private struct ThrowingMiddleware: DeepLinkMiddleware {
	func intercept(_: DeepLinkRequest) async throws -> DeepLinkRequest? {
		throw DeepLinkError.securityViolation("test")
	}
}
