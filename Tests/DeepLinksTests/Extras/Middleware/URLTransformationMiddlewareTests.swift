//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct URLTransformationMiddlewareTests {
	@Test
	func `URLTransformationMiddleware transforms URLs using provided transformer`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let transformedURL = try #require(URL(string: "testapp://transformed"))
		let transformerStub = URLTransformerStub(transformedURL: transformedURL)
		let middleware = URLTransformationMiddleware(transformer: transformerStub)

		let result = try await middleware.intercept(testURL)

		#expect(result == transformedURL)
	}

	@Test
	func `URLTransformationMiddleware propagates transformer errors`() async throws {
		let testURL = try #require(URL(string: "testapp://test"))
		let errorTransformer = ErrorThrowingTransformer()
		let middleware = URLTransformationMiddleware(transformer: errorTransformer)

		do {
			_ = try await middleware.intercept(testURL)
			#expect(Bool(false), "Expected transformer error")
		} catch let error as DeepLinkError {
			#expect(error == .handlerError("Transformer error"))
		}
	}

	// MARK: - Test Helpers

	private final class URLTransformerStub: URLTransformer {
		private let transformedURL: URL

		init(transformedURL: URL) {
			self.transformedURL = transformedURL
		}

		func transform(_: URL) throws -> URL {
			transformedURL
		}
	}

	private final class ErrorThrowingTransformer: URLTransformer {
		func transform(_: URL) throws -> URL {
			throw DeepLinkError.handlerError("Transformer error")
		}
	}
}
