//
//  Copyright © 2025 Jesús Alfredo Hernández Alarcón. All rights reserved.
//

@testable import DeepLink
import Foundation
import Testing

@Suite("DeepLinkURL Tests")
struct DeepLinkURLTests {
    @Test("DeepLinkURL init returns valid instance with complete URL")
    func deepLinkURL_init_returnsValidInstanceWithCompleteURL() throws {
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

    @Test("DeepLinkURL init returns valid instance with path component")
    func deepLinkURL_init_returnsValidInstanceWithPathComponent() throws {
        let urlString = "myapp://product/electronics?category=phones"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "product")
        #expect(deepLinkURL.path == "/electronics")
        #expect(deepLinkURL.queryParameters["category"] == "phones")
    }

    @Test("DeepLinkURL init returns valid instance with empty query parameters")
    func deepLinkURL_init_returnsValidInstanceWithEmptyQueryParameters() throws {
        let urlString = "myapp://settings"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "settings")
        #expect(deepLinkURL.path == "")
        #expect(deepLinkURL.queryParameters.isEmpty)
    }

    @Test("DeepLinkURL init returns valid instance with multiple query parameters")
    func deepLinkURL_init_returnsValidInstanceWithMultipleQueryParameters() throws {
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

    @Test("DeepLinkURL init returns valid instance with URL encoded parameters")
    func deepLinkURL_init_returnsValidInstanceWithURLEncodedParameters() throws {
        let urlString = "myapp://info?title=News%20%26%20Updates&brief=Latest%20information%20about%20our%20app"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "info")
        #expect(deepLinkURL.queryParameters["title"] == "News & Updates")
        #expect(deepLinkURL.queryParameters["brief"] == "Latest information about our app")
    }

    @Test("DeepLinkURL init returns valid instance with special characters in host")
    func deepLinkURL_init_returnsValidInstanceWithSpecialCharactersInHost() throws {
        let urlString = "myapp://user-profile?userId=123"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "user-profile")
        #expect(deepLinkURL.queryParameters["userId"] == "123")
    }

    @Test("DeepLinkURL init returns valid instance with complex path")
    func deepLinkURL_init_returnsValidInstanceWithComplexPath() throws {
        let urlString = "myapp://api/v1/users/123/profile?include=settings,preferences"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "api")
        #expect(deepLinkURL.path == "/v1/users/123/profile")
        #expect(deepLinkURL.queryParameters["include"] == "settings,preferences")
    }

    @Test("DeepLinkURL init returns valid instance with empty host")
    func deepLinkURL_init_returnsValidInstanceWithEmptyHost() throws {
        let urlWithEmptyHost = try #require(URL(string: "myapp://"))
        let deepLinkURL = try DeepLinkURL(url: urlWithEmptyHost)

        #expect(deepLinkURL.scheme == "myapp")
        #expect(deepLinkURL.host == "")
        #expect(deepLinkURL.path == "")
        #expect(deepLinkURL.queryParameters.isEmpty)
    }

    @Test("DeepLinkURL init ignores query parameters with nil values")
    func deepLinkURL_init_ignoresQueryParametersWithNilValues() throws {
        let urlString = "myapp://test?valid=value&invalid&another=test"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.queryParameters.count == 2)
        #expect(deepLinkURL.queryParameters["valid"] == "value")
        #expect(deepLinkURL.queryParameters["another"] == "test")
        #expect(deepLinkURL.queryParameters["invalid"] == nil)
    }

    @Test("DeepLinkURL init handles empty query parameter values")
    func deepLinkURL_init_handlesEmptyQueryParameterValues() throws {
        let urlString = "myapp://test?empty=&normal=value"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.queryParameters.count == 2)
        #expect(deepLinkURL.queryParameters["empty"] == "")
        #expect(deepLinkURL.queryParameters["normal"] == "value")
    }

    @Test("DeepLinkURL init handles query parameters with special characters")
    func deepLinkURL_init_handlesQueryParametersWithSpecialCharacters() throws {
        let urlString = "myapp://test?param1=value1&param2=value2"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.queryParameters.count == 2)
        #expect(deepLinkURL.queryParameters["param1"] == "value1")
        #expect(deepLinkURL.queryParameters["param2"] == "value2")
    }

    @Test("DeepLinkURL init throws invalidURL error on malformed URL")
    func deepLinkURL_init_throwsInvalidURLErrorOnMalformedURL() {
        let malformedURL = URL(string: "not-a-valid-url")!

        #expect(throws: DeepLinkError.invalidURL(malformedURL)) {
            try DeepLinkURL(url: malformedURL)
        }
    }

    @Test("DeepLinkURL init throws invalidURL error on URL without scheme")
    func deepLinkURL_init_throwsInvalidURLErrorOnURLWithoutScheme() {
        let urlWithoutScheme = URL(string: "//profile?userId=123")!

        #expect(throws: DeepLinkError.invalidURL(urlWithoutScheme)) {
            try DeepLinkURL(url: urlWithoutScheme)
        }
    }

    @Test("DeepLinkURL init throws invalidURL error on empty URL")
    func deepLinkURL_init_throwsInvalidURLErrorOnEmptyURL() {
        let emptyURL = URL(string: "not-a-valid-url")!

        #expect(throws: DeepLinkError.invalidURL(emptyURL)) {
            try DeepLinkURL(url: emptyURL)
        }
    }

    // MARK: - Array Query Parameters Tests

    @Test("DeepLinkURL allQueryParameters handles single value parameters")
    func deepLinkURL_allQueryParameters_handlesSingleValueParameters() throws {
        let urlString = "myapp://profile?userId=123&name=John"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.allQueryParameters["userId"] == ["123"])
        #expect(deepLinkURL.allQueryParameters["name"] == ["John"])
        #expect(deepLinkURL.allQueryParameters.count == 2)
    }

    @Test("DeepLinkURL allQueryParameters handles multiple values for same key")
    func deepLinkURL_allQueryParameters_handlesMultipleValuesForSameKey() throws {
        let urlString = "myapp://products?tags=electronics&tags=new&tags=sale"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.allQueryParameters["tags"] == ["electronics", "new", "sale"])
        #expect(deepLinkURL.allQueryParameters.count == 1)
    }

    @Test("DeepLinkURL allQueryParameters handles mixed single and multiple values")
    func deepLinkURL_allQueryParameters_handlesMixedSingleAndMultipleValues() throws {
        let urlString = "myapp://products?category=phones&tags=electronics&tags=new&brand=Apple"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.allQueryParameters["category"] == ["phones"])
        #expect(deepLinkURL.allQueryParameters["tags"] == ["electronics", "new"])
        #expect(deepLinkURL.allQueryParameters["brand"] == ["Apple"])
        #expect(deepLinkURL.allQueryParameters.count == 3)
    }

    @Test("DeepLinkURL queryParameters returns last value when multiple values exist")
    func deepLinkURL_queryParameters_returnsLastValueWhenMultipleValuesExist() throws {
        let urlString = "myapp://products?tags=electronics&tags=new&tags=sale"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        // queryParameters should only have the last value
        #expect(deepLinkURL.queryParameters["tags"] == "sale")
        #expect(deepLinkURL.queryParameters.count == 1)
    }

    @Test("DeepLinkURL allQueryParameters handles empty parameters")
    func deepLinkURL_allQueryParameters_handlesEmptyParameters() throws {
        let urlString = "myapp://settings"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.allQueryParameters.isEmpty)
    }

    @Test("DeepLinkURL allQueryParameters handles URL encoded array values")
    func deepLinkURL_allQueryParameters_handlesURLEncodedArrayValues() throws {
        let urlString = "myapp://products?tags=new%20arrivals&tags=best%20sellers&tags=on%20sale"
        let url = try #require(URL(string: urlString))
        let deepLinkURL = try DeepLinkURL(url: url)

        #expect(deepLinkURL.allQueryParameters["tags"] == ["new arrivals", "best sellers", "on sale"])
    }
}
