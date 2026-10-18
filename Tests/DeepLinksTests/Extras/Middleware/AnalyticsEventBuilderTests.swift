//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. Licensed under the MIT License.
//

@testable import DeepLinks
import Foundation
import Testing

struct AnalyticsEventBuilderTests {
	private static let fullURL = URL(string: "myapp://product/123?category=electronics")!

	@Test
	func `hostOnly detail emits scheme, host, and timestamp only`() {
		let parameters = AnalyticsEventBuilder.parameters(for: Self.fullURL, detail: .hostOnly)

		#expect(parameters["scheme"] as? String == "myapp")
		#expect(parameters["host"] as? String == "product")
		#expect(parameters["timestamp"] as? TimeInterval != nil)
		#expect(parameters["url"] == nil)
		#expect(parameters["path"] == nil)
		#expect(parameters.keys.sorted() == ["host", "scheme", "timestamp"])
	}

	@Test
	func `withURL detail adds url on top of scheme, host, and timestamp`() {
		let parameters = AnalyticsEventBuilder.parameters(for: Self.fullURL, detail: .withURL)

		#expect(parameters["scheme"] as? String == "myapp")
		#expect(parameters["host"] as? String == "product")
		#expect(parameters["url"] as? String == Self.fullURL.absoluteString)
		#expect(parameters["timestamp"] as? TimeInterval != nil)
		#expect(parameters["path"] == nil)
		#expect(parameters.keys.sorted() == ["host", "scheme", "timestamp", "url"])
	}

	@Test
	func `full detail adds url and path on top of scheme, host, and timestamp`() {
		let parameters = AnalyticsEventBuilder.parameters(for: Self.fullURL, detail: .full)

		#expect(parameters["scheme"] as? String == "myapp")
		#expect(parameters["host"] as? String == "product")
		#expect(parameters["url"] as? String == Self.fullURL.absoluteString)
		#expect(parameters["path"] as? String == "/123")
		#expect(parameters["timestamp"] as? TimeInterval != nil)
		#expect(parameters.keys.sorted() == ["host", "path", "scheme", "timestamp", "url"])
	}

	@Test
	func `fullOmittingEmptyPath detail includes path when the URL has one`() {
		let parameters = AnalyticsEventBuilder.parameters(for: Self.fullURL, detail: .fullOmittingEmptyPath)

		#expect(parameters["scheme"] as? String == "myapp")
		#expect(parameters["host"] as? String == "product")
		#expect(parameters["url"] as? String == Self.fullURL.absoluteString)
		#expect(parameters["path"] as? String == "/123")
		#expect(parameters["timestamp"] as? TimeInterval != nil)
		// Lock the key set so a future change that adds a spurious key (for
		// example a `fragment` or correlation identifier) fails this test
		// instead of silently widening the analytics envelope.
		#expect(parameters.keys.sorted() == ["host", "path", "scheme", "timestamp", "url"])
	}

	@Test
	func `fullOmittingEmptyPath detail omits path when the URL has no path`() throws {
		let pathlessURL = try #require(URL(string: "myapp://product"))
		let parameters = AnalyticsEventBuilder.parameters(for: pathlessURL, detail: .fullOmittingEmptyPath)

		#expect(parameters["scheme"] as? String == "myapp")
		#expect(parameters["host"] as? String == "product")
		#expect(parameters["url"] as? String == pathlessURL.absoluteString)
		#expect(parameters["path"] == nil)
		#expect(parameters.keys.sorted() == ["host", "scheme", "timestamp", "url"])
	}

	@Test
	func `full detail keeps an empty path key even when the URL has no path`() throws {
		let pathlessURL = try #require(URL(string: "myapp://product"))
		let parameters = AnalyticsEventBuilder.parameters(for: pathlessURL, detail: .full)

		#expect(parameters["path"] as? String == "")
		#expect(parameters.keys.contains("path"))
		#expect(parameters.keys.sorted() == ["host", "path", "scheme", "timestamp", "url"])
	}

	@Test
	func `missing scheme and host fall back to the string "unknown"`() throws {
		let hostlessURL = try #require(URL(string: "test:///"))
		let parameters = AnalyticsEventBuilder.parameters(for: hostlessURL, detail: .full)

		#expect(parameters["host"] as? String == "unknown")
	}

	@Test
	func `timestamp is a Unix-epoch TimeInterval close to now`() {
		let before = Date().timeIntervalSince1970
		let parameters = AnalyticsEventBuilder.parameters(for: Self.fullURL, detail: .hostOnly)
		let after = Date().timeIntervalSince1970

		let timestamp = try? #require(parameters["timestamp"] as? TimeInterval)
		#expect(timestamp.map { $0 >= before && $0 <= after } == true)
	}
}
