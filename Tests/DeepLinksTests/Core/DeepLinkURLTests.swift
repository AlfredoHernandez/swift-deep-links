//
//  Copyright © 2026 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLinks
import Foundation
import Testing

struct DeepLinkURLTests {
	@Test
	func `DeepLinkURL init returns valid instance with complete URL`() throws {
		let urlString = "myapp://profile?userId=123&name=John%20Doe"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "profile")
		#expect(deepLinkURL.path == "")
		#expect(deepLinkURL.queryParameters["userId"] == "123")
		#expect(deepLinkURL.queryParameters["name"] == "John Doe")
		#expect(deepLinkURL.url == url)
	}

	@Test
	func `DeepLinkURL init returns valid instance with path component`() throws {
		let urlString = "myapp://product/electronics?category=phones"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "product")
		#expect(deepLinkURL.path == "/electronics")
		#expect(deepLinkURL.queryParameters["category"] == "phones")
	}

	@Test
	func `DeepLinkURL init returns valid instance with empty query parameters`() throws {
		let urlString = "myapp://settings"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "settings")
		#expect(deepLinkURL.path == "")
		#expect(deepLinkURL.queryParameters.isEmpty)
	}

	@Test
	func `DeepLinkURL init returns valid instance with multiple query parameters`() throws {
		let urlString = "myapp://alert?title=Error&message=Something%20went%20wrong&type=error&retry=true"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "alert")
		#expect(deepLinkURL.queryParameters.count == 4)
		#expect(deepLinkURL.queryParameters["title"] == "Error")
		#expect(deepLinkURL.queryParameters["message"] == "Something went wrong")
		#expect(deepLinkURL.queryParameters["type"] == "error")
		#expect(deepLinkURL.queryParameters["retry"] == "true")
	}

	@Test
	func `DeepLinkURL init returns valid instance with URL encoded parameters`() throws {
		let urlString = "myapp://info?title=News%20%26%20Updates&brief=Latest%20information%20about%20our%20app"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "info")
		#expect(deepLinkURL.queryParameters["title"] == "News & Updates")
		#expect(deepLinkURL.queryParameters["brief"] == "Latest information about our app")
	}

	@Test
	func `DeepLinkURL init returns valid instance with special characters in host`() throws {
		let urlString = "myapp://user-profile?userId=123"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "user-profile")
		#expect(deepLinkURL.queryParameters["userId"] == "123")
	}

	@Test
	func `DeepLinkURL init returns valid instance with complex path`() throws {
		let urlString = "myapp://api/v1/users/123/profile?include=settings,preferences"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "api")
		#expect(deepLinkURL.path == "/v1/users/123/profile")
		#expect(deepLinkURL.queryParameters["include"] == "settings,preferences")
	}

	@Test
	func `DeepLinkURL init returns valid instance with empty host`() throws {
		let urlWithEmptyHost = try #require(URL(string: "myapp://"))
		let deepLinkURL = try DeepLinkURL(url: urlWithEmptyHost)

		#expect(deepLinkURL.scheme == "myapp")
		#expect(deepLinkURL.host == "")
		#expect(deepLinkURL.path == "")
		#expect(deepLinkURL.queryParameters.isEmpty)
	}

	@Test
	func `DeepLinkURL init ignores query parameters with nil values`() throws {
		let urlString = "myapp://test?valid=value&invalid&another=test"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.queryParameters.count == 2)
		#expect(deepLinkURL.queryParameters["valid"] == "value")
		#expect(deepLinkURL.queryParameters["another"] == "test")
		#expect(deepLinkURL.queryParameters["invalid"] == nil)
	}

	@Test
	func `DeepLinkURL init handles empty query parameter values`() throws {
		let urlString = "myapp://test?empty=&normal=value"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.queryParameters.count == 2)
		#expect(deepLinkURL.queryParameters["empty"] == "")
		#expect(deepLinkURL.queryParameters["normal"] == "value")
	}

	@Test
	func `DeepLinkURL init handles query parameters with special characters`() throws {
		let urlString = "myapp://test?param1=value1&param2=value2"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.queryParameters.count == 2)
		#expect(deepLinkURL.queryParameters["param1"] == "value1")
		#expect(deepLinkURL.queryParameters["param2"] == "value2")
	}

	@Test
	func `DeepLinkURL init throws invalidURL error on malformed URL`() throws {
		let malformedURL = try #require(URL(string: "not-a-valid-url"))

		#expect(throws: DeepLinkError.invalidURL(malformedURL)) {
			try DeepLinkURL(url: malformedURL)
		}
	}

	@Test
	func `DeepLinkURL init throws invalidURL error on URL without scheme`() throws {
		let urlWithoutScheme = try #require(URL(string: "//profile?userId=123"))

		#expect(throws: DeepLinkError.invalidURL(urlWithoutScheme)) {
			try DeepLinkURL(url: urlWithoutScheme)
		}
	}

	@Test
	func `DeepLinkURL init throws invalidURL error on empty URL`() throws {
		let emptyURL = try #require(URL(string: "not-a-valid-url"))

		#expect(throws: DeepLinkError.invalidURL(emptyURL)) {
			try DeepLinkURL(url: emptyURL)
		}
	}

	// MARK: - Array Query Parameters Tests

	@Test
	func `DeepLinkURL allQueryParameters handles single value parameters`() throws {
		let urlString = "myapp://profile?userId=123&name=John"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.allQueryParameters["userId"] == ["123"])
		#expect(deepLinkURL.allQueryParameters["name"] == ["John"])
		#expect(deepLinkURL.allQueryParameters.count == 2)
	}

	@Test
	func `DeepLinkURL allQueryParameters handles multiple values for same key`() throws {
		let urlString = "myapp://products?tags=electronics&tags=new&tags=sale"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.allQueryParameters["tags"] == ["electronics", "new", "sale"])
		#expect(deepLinkURL.allQueryParameters.count == 1)
	}

	@Test
	func `DeepLinkURL allQueryParameters handles mixed single and multiple values`() throws {
		let urlString = "myapp://products?category=phones&tags=electronics&tags=new&brand=Apple"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.allQueryParameters["category"] == ["phones"])
		#expect(deepLinkURL.allQueryParameters["tags"] == ["electronics", "new"])
		#expect(deepLinkURL.allQueryParameters["brand"] == ["Apple"])
		#expect(deepLinkURL.allQueryParameters.count == 3)
	}

	@Test
	func `DeepLinkURL queryParameters returns last value when multiple values exist`() throws {
		let urlString = "myapp://products?tags=electronics&tags=new&tags=sale"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		// queryParameters should only have the last value
		#expect(deepLinkURL.queryParameters["tags"] == "sale")
		#expect(deepLinkURL.queryParameters.count == 1)
	}

	@Test
	func `DeepLinkURL allQueryParameters handles empty parameters`() throws {
		let urlString = "myapp://settings"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.allQueryParameters.isEmpty)
	}

	@Test
	func `DeepLinkURL allQueryParameters handles URL encoded array values`() throws {
		let urlString = "myapp://products?tags=new%20arrivals&tags=best%20sellers&tags=on%20sale"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url)

		#expect(deepLinkURL.allQueryParameters["tags"] == ["new arrivals", "best sellers", "on sale"])
	}

	// MARK: - URL Length Validation Tests

	@Test
	func `DeepLinkURL init throws invalidURL when URL exceeds maxLength`() throws {
		let longParam = String(repeating: "a", count: 100)
		let urlString = "myapp://test?\(longParam)=value"
		let url = try #require(URL(string: urlString))

		#expect(throws: DeepLinkError.invalidURL(url)) {
			try DeepLinkURL(url: url, maxLength: 50)
		}
	}

	@Test
	func `DeepLinkURL init succeeds when URL is within maxLength`() throws {
		let url = try #require(URL(string: "myapp://test?key=value"))
		let deepLinkURL = try DeepLinkURL(url: url, maxLength: 1000)

		#expect(deepLinkURL.host == "test")
	}

	@Test
	func `DeepLinkURL init succeeds when URL is exactly at maxLength`() throws {
		let urlString = "myapp://test"
		let url = try #require(URL(string: urlString))
		let deepLinkURL = try DeepLinkURL(url: url, maxLength: urlString.count)

		#expect(deepLinkURL.host == "test")
	}

	@Test
	func `DeepLinkURL init throws when URL exceeds default maxLength`() throws {
		let longParam = String(repeating: "x", count: DeepLinkURL.defaultMaxLength)
		let urlString = "myapp://test?\(longParam)"
		let url = try #require(URL(string: urlString))

		#expect(throws: DeepLinkError.invalidURL(url)) {
			try DeepLinkURL(url: url)
		}
	}
}
